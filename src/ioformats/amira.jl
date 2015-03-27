module Amira

using Images
import Images.imread, Images.imwrite
import Zlib
import Dates


function decodeRLE!(in::Array{Uint8,1}, out::Array{Uint8,1})
	outIdx = 1
	inIdx = 1
	while inIdx<=length(in) && outIdx<=length(out)
		num = int(in[inIdx]) 
		if num == 0
			warn("RLE: num is 0")
			return
		end
		val = in[inIdx+1]
		
		if num>127
			num = num & 127
			for i=0:num-1
				out[outIdx+i] = in[inIdx + 1 + i] 
			end
			inIdx += 1+num
		else
			for i=0:num-1
				out[outIdx+i] = val
			end
			inIdx += 2
		end
		outIdx += num
	end
end

function imread{S<:IO}(stream::S, ::Type{Images.AmiraFile})

	rLattice = r"define\s+Lattice\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)"
	rBounds = r"BoundingBox\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)"
	rData =  r"Lattice\s+\{\s+byte\s+(.+)\s+\}(\s+=)?\s+@1(\((.+),([0-9]+)\))?"
	rMark = r"\n@1\n"

	header = ASCIIString(readbytes(stream, 1024))
	
	mLattice = match(rLattice, header)
	mBounds = match(rBounds, header)
	mData = match(rData, header)
	mMark = match(rMark, header)
	if mLattice == nothing
		warn("Lattice cannot be parsed")
		nothing
	elseif mBounds == nothing
		warn("bounds could not be parsed")
		nothing
	elseif mData == nothing
		warn("Data cannot be parsed")
		nothing
	elseif mMark == nothing
		warn("data mark cannot be found")
		nothing
	else
		sx = int(mLattice.captures[1])		
		sy = int(mLattice.captures[2])		
		sz = int(mLattice.captures[3])
		
		vsx = (float64(mBounds.captures[2]) - float64(mBounds.captures[1])) / sx
		vsy = (float64(mBounds.captures[4]) - float64(mBounds.captures[3])) / sy
		vsz = (float64(mBounds.captures[6]) - float64(mBounds.captures[5])) / sz

		offset = mMark.offset + 3

		seek(stream, offset)

		if mData.captures[4] == nothing # No compression

			idata = read(stream, Uint8, (sx, sy, sz))

			img = Image(idata, pixelspacing = [vsx,vsy,vsz])
			img
		elseif mData.captures[4] == "HxZip" # ZipCompressed
			len = int(mData.captures[5])
			rawdata = Array(Uint8, len)
			read!(file,rawdata)
			data = Zlib.decompress(rawdata)
			idata = reshape(data, sx,sy,sz)
			img = Image(idata, pixelspacing = [vsx,vsy,vsz])
			img
		elseif mData.captures[4] == "HxByteRLE" # run length encoded
			len = int(mData.captures[5])
			rawdata = Array(Uint8, len)
			read!(stream,rawdata)
			data = Array(Uint8, sx*sy*sz)
			decodeRLE!(rawdata, data)
			idata = reshape(data, sx,sy,sz)
			img = Image(idata, pixelspacing = [vsx,vsy,vsz])
			img
		end
	end
	img
end

function imwrite(img, filename::String, ::Type{Images.AmiraFile})
	open(filename, "w") do file
		(sx, sy, sz) = size(img.data)
		bdata = if typeof(img.data) == Array{Uint8,3}
			reshape(img.data, sx*sy*sz)
		else
			map(x-> uint8(x*255), reshape(img.data, sx*sy*sz))
		end
			
		cdata = Zlib.compress(bdata)
		(vsx,vsy,vsz) = if haskey(img, "pixelspacing")
			img["pixelspacing"]
		else
			(1.0,1.0,1.0)
		end
		write(file, "# AmiraMesh 3D BINARY-LITTLE-ENDIAN 2.0\n\n")
		write(file, "# CreationDate: $(Dates.now())\n\n\n")
		write(file, "define Lattice $sx $sy $sz\n\n")
		write(file, "Parameters {\n")
		write(file, "	Content \"$(sx)x$(sy)x$(sz) byte, uniform coordinates\"\n")
		write(file, "	BoundingBox 0.000000 $(sx*vsx) 0.000000 $(sy*vsy) 0.000000 $(sz*vsz),\n")
		write(file, "	CoordType \"uniform\"\n")
		write(file, "}\n\n")
		write(file, "Lattice { byte Data } @1(HxZip,$(length(cdata)))\n")
		write(file, "# Data section follows\n")
		write(file, "@1\n")

		write(file, cdata)
	end
end

end
