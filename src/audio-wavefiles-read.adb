-------------------------------------------------------------------------------
--
--                                WAVEFILES
--
--                            Wavefile reading
--
--  The MIT License (MIT)
--
--  Copyright (c) 2015 -- 2020 Gustavo A. Hoffmann
--
--  Permission is hereby granted, free of charge, to any person obtaining a
--  copy of this software and associated documentation files (the "Software"),
--  to deal in the Software without restriction, including without limitation
--  the rights to use, copy, modify, merge, publish, distribute, sublicense,
--  and / or sell copies of the Software, and to permit persons to whom the
--  Software is furnished to do so, subject to the following conditions:
--
--  The above copyright notice and this permission notice shall be included in
--  all copies or substantial portions of the Software.
--
--  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
--  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
--  DEALINGS IN THE SOFTWARE.
-------------------------------------------------------------------------------

with Ada.Text_IO;                  use Ada.Text_IO;
with Interfaces;

with Audio.RIFF;                   use Audio.RIFF;
with Audio.Wavefiles.Internals;    use Audio.Wavefiles.Internals;

package body Audio.Wavefiles.Read is

   procedure Parse_Fmt_Chunk
     (WF : in out Wavefile);
   procedure Parse_Data_Chunk
     (WF : in out Wavefile);

   procedure Parse_Fmt_Chunk
     (WF : in out Wavefile)
   is
      Verbose : constant Boolean := False;

      use type Ada.Streams.Stream_IO.Count;
   begin
      for Chunk_Element of WF.RIFF_Info.Chunks loop

         if Chunk_Element.Chunk_Tag = Wav_Chunk_Fmt then
            Set_File_Index_To_Chunk_Data_Start (WF.File,
                                                Chunk_Element.Start_Index);

            case Chunk_Element.Size is
            when Wave_Format_Chunk_Size'Enum_Rep (Wave_Format_16_Size) =>
               Wave_Format_16'Read (WF.File_Access,
                                    Wave_Format_16 (WF.Wave_Format));
               Reset_For_Wave_Format_16 (WF.Wave_Format);
            when Wave_Format_Chunk_Size'Enum_Rep (Wave_Format_18_Size) =>
               Wave_Format_18'Read (WF.File_Access,
                                    Wave_Format_18 (WF.Wave_Format));
               Reset_For_Wave_Format_18 (WF.Wave_Format);

               if Verbose then
                  Put_Line ("Size of waveformat record "
                            & Integer'Image (
                              Wave_Format_18'Value_Size / 8));
                  Put_Line ("BitsPerSample: "
                            & Positive'Image
                              (To_Positive (WF.Wave_Format.Bits_Per_Sample)));
                  Put_Line ("Size: " & Interfaces.Unsigned_16'Image
                            (WF.Wave_Format.Size));
               end if;

            when Wave_Format_Chunk_Size'Enum_Rep
                 (Wave_Format_Extensible_Size) =>
               Wave_Format_Extensible'Read (WF.File_Access,
                                            WF.Wave_Format);

               if Verbose then
                  Put_Line ("Size of waveformat record "
                            & Integer'Image
                              (Wave_Format_Extensible'Value_Size / 8));
                  Put_Line ("File index: " & Integer'Image (
                            Integer (Ada.Streams.Stream_IO.Index (WF.File))));
                  Put_Line ("BitsPerSample: "
                            & Positive'Image
                              (To_Positive (WF.Wave_Format.Bits_Per_Sample)));
                  Put_Line ("Size: " & Interfaces.Unsigned_16'Image
                            (WF.Wave_Format.Size));
               end if;

            when others =>
               raise Wavefile_Error;
            end case;

            if Verbose then
               Display_Info (WF);
               Put_Line ("fmt chunk size: " & Long_Integer'Image
                         (Chunk_Element.Size));
            end if;

            exit;
         end if;

      end loop;
   end Parse_Fmt_Chunk;

   procedure Parse_Data_Chunk
     (WF : in out Wavefile)
   is
      Verbose : constant Boolean := False;
   begin
      for Chunk_Element of WF.RIFF_Info.Chunks loop

         if Chunk_Element.Chunk_Tag = Wav_Chunk_Data then
            Set_File_Index_To_Chunk_Data_Start (WF.File,
                                                Chunk_Element.Start_Index);

            if Verbose then
               Put_Line ("RIFF Tag: " & Chunk_Element.ID);
            end if;

            WF.Samples := Chunk_Element.Size /
              (Long_Integer (To_Positive (WF.Wave_Format.Bits_Per_Sample))
               / 8);

            if Verbose then
               Put_Line ("Data chunk size: " & Long_Integer'Image
                         (Chunk_Element.Size));
               Put_Line ("Num samples: " & Long_Integer'Image (WF.Samples));
               Put_Line ("Num samples: " & Long_Integer'Image (WF.Samples
                         / Long_Integer (WF.Wave_Format.Channels)));
            end if;

            exit;
         end if;

      end loop;
   end Parse_Data_Chunk;

   procedure Read_Until_Data_Start
     (WF          : in out Wavefile)
   is
      Verbose      : constant Boolean := False;
   begin
      if WF.RIFF_Info.Chunks.Is_Empty then
         Audio.Wavefiles.Read.Parse_Wav_Chunks (WF);
      end if;

      if Verbose then
         Put_Line ("--------------------------------");
         Put_Line (WF.RIFF_Info.Id'Image);
         Put_Line (WF.RIFF_Info.Format'Image);
         Put_Line (WF.RIFF_Info.Chunks.Length'Image);
         for E of WF.RIFF_Info.Chunks loop
            Put_Line ("---- Chunk");
            Put_Line (E.Chunk_Tag'Image);
            Put_Line (E.ID);
            Put_Line (E.Size'Image);
            Put_Line (E.Start_Index'Image);
            Put_Line (E.Consolidated'Image);
         end loop;
         Put_Line ("--------------------------------");
      end if;

      Parse_Fmt_Chunk (WF);

      Parse_Data_Chunk (WF);

   end Read_Until_Data_Start;

   procedure Parse_Wav_Chunks
     (WF     : in out Wavefile)
   is
      use Ada.Streams;

      Prev_File_Index : constant Ada.Streams.Stream_IO.Positive_Count :=
                          Stream_IO.Index (WF.File);
      Curr_File_Index :          Ada.Streams.Stream_IO.Positive_Count;

      Chunk_Header    : RIFF_Chunk_Header;

      Info            : RIFF_Information renames WF.RIFF_Info;
   begin
      --  Set index to initial RIFF chunk
      Ada.Streams.Stream_IO.Set_Index (WF.File, 1);

      Info.Chunks.Clear;

      Parse_RIFF_Header : declare
         FOURCC : FOURCC_String;
      begin
         RIFF_Chunk_Header'Read (WF.File_Access, Chunk_Header);
         FOURCC_String'Read (WF.File_Access, FOURCC);

         Info.Id     := To_RIFF_Identifier (Chunk_Header.ID);
         Info.Format := To_RIFF_Format (FOURCC);
      end Parse_RIFF_Header;

      if Info.Id    /= RIFF_Identifier_Unknown and then
        Info.Format /= RIFF_Format_Unknown
      then
         loop
            Curr_File_Index := Ada.Streams.Stream_IO.Index (WF.File);

            RIFF_Chunk_Header'Read (WF.File_Access, Chunk_Header);

            declare
               Chunk_Element      : constant Wav_Chunk_Element
                 := (Chunk_Tag    => To_Wav_Chunk_Tag (Chunk_Header.ID),
                     ID           => Chunk_Header.ID,
                     Size         => Long_Integer (Chunk_Header.Size),
                     Start_Index  => Curr_File_Index,
                     Consolidated => True);
            begin
               Info.Chunks.Append (Chunk_Element);
            end;

            Skip_Bytes (WF.File, Chunk_Header.Size);

            exit when Ada.Streams.Stream_IO.End_Of_File (WF.File);
         end loop;
      end if;

      --  Setting file index back to previous location
      Ada.Streams.Stream_IO.Set_Index (WF.File, Prev_File_Index);
   end Parse_Wav_Chunks;

end Audio.Wavefiles.Read;
