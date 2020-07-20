// Code generated by protoc-gen-gogo. DO NOT EDIT.
// source: build/info.proto

package build

import (
	fmt "fmt"
	_ "github.com/gogo/protobuf/gogoproto"
	proto "github.com/gogo/protobuf/proto"
	io "io"
	math "math"
	math_bits "math/bits"
)

// Reference imports to suppress errors if they are not otherwise used.
var _ = proto.Marshal
var _ = fmt.Errorf
var _ = math.Inf

// This is a compile-time assertion to ensure that this generated file
// is compatible with the proto package it is being compiled against.
// A compilation error at this line likely means your copy of the
// proto package needs to be updated.
const _ = proto.GoGoProtoPackageIsVersion2 // please upgrade the proto package

// Info describes build information for this CockroachDB binary.
type Info struct {
	GoVersion       string `protobuf:"bytes,1,opt,name=go_version,json=goVersion" json:"go_version"`
	Tag             string `protobuf:"bytes,2,opt,name=tag" json:"tag"`
	Time            string `protobuf:"bytes,3,opt,name=time" json:"time"`
	Revision        string `protobuf:"bytes,4,opt,name=revision" json:"revision"`
	CgoCompiler     string `protobuf:"bytes,5,opt,name=cgo_compiler,json=cgoCompiler" json:"cgo_compiler"`
	CgoTargetTriple string `protobuf:"bytes,10,opt,name=cgo_target_triple,json=cgoTargetTriple" json:"cgo_target_triple"`
	Platform        string `protobuf:"bytes,6,opt,name=platform" json:"platform"`
	Distribution    string `protobuf:"bytes,7,opt,name=distribution" json:"distribution"`
	Type            string `protobuf:"bytes,8,opt,name=type" json:"type"`
	Channel         string `protobuf:"bytes,9,opt,name=channel" json:"channel"`
	EnvChannel      string `protobuf:"bytes,11,opt,name=env_channel,json=envChannel" json:"env_channel"`
	// dependencies exists to allow tests that run against old clusters
	// to unmarshal JSON containing this field. The tag is unimportant,
	// but the field name must remain unchanged.
	//
	// alternatively, we could set jsonpb.Unmarshaler.AllowUnknownFields
	// to true in httputil.doJSONRequest, but that comes at the expense
	// of run-time type checking, which is nice to have.
	Dependencies *string `protobuf:"bytes,10000,opt,name=dependencies" json:"dependencies,omitempty"`
}

func (m *Info) Reset()         { *m = Info{} }
func (m *Info) String() string { return proto.CompactTextString(m) }
func (*Info) ProtoMessage()    {}
func (*Info) Descriptor() ([]byte, []int) {
	return fileDescriptor_4e07f274d5866c11, []int{0}
}
func (m *Info) XXX_Unmarshal(b []byte) error {
	return m.Unmarshal(b)
}
func (m *Info) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	b = b[:cap(b)]
	n, err := m.MarshalTo(b)
	if err != nil {
		return nil, err
	}
	return b[:n], nil
}
func (m *Info) XXX_Merge(src proto.Message) {
	xxx_messageInfo_Info.Merge(m, src)
}
func (m *Info) XXX_Size() int {
	return m.Size()
}
func (m *Info) XXX_DiscardUnknown() {
	xxx_messageInfo_Info.DiscardUnknown(m)
}

var xxx_messageInfo_Info proto.InternalMessageInfo

func init() {
	proto.RegisterType((*Info)(nil), "cockroach.build.Info")
}

func init() { proto.RegisterFile("build/info.proto", fileDescriptor_4e07f274d5866c11) }

var fileDescriptor_4e07f274d5866c11 = []byte{
	// 338 bytes of a gzipped FileDescriptorProto
	0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0x54, 0x91, 0x31, 0x8e, 0x1a, 0x31,
	0x14, 0x40, 0x67, 0xc2, 0x10, 0xc0, 0x20, 0x91, 0x58, 0x51, 0x64, 0xa5, 0x70, 0x50, 0x50, 0x04,
	0x15, 0xe4, 0x0c, 0x50, 0xa5, 0xd9, 0x02, 0xa1, 0x2d, 0xb6, 0x19, 0x0d, 0x9e, 0x8f, 0xb1, 0x76,
	0xf0, 0x1f, 0x19, 0x33, 0x12, 0xb7, 0xe0, 0x20, 0x7b, 0x10, 0x4a, 0x4a, 0xaa, 0xd5, 0xee, 0x70,
	0x91, 0xd5, 0x18, 0x58, 0x99, 0xce, 0x7a, 0xef, 0xc9, 0xdf, 0x5f, 0x26, 0xdf, 0x16, 0x5b, 0x95,
	0xa5, 0x63, 0xa5, 0x97, 0x38, 0xca, 0x0d, 0x5a, 0xa4, 0x5d, 0x81, 0xe2, 0xd9, 0x60, 0x22, 0x56,
	0x23, 0xe7, 0x7e, 0xfd, 0x90, 0x28, 0xd1, 0xb9, 0x71, 0x75, 0xba, 0x64, 0x7f, 0x5e, 0x6a, 0x24,
	0xfa, 0xaf, 0x97, 0x48, 0xfb, 0x84, 0x48, 0x8c, 0x0b, 0x30, 0x1b, 0x85, 0x9a, 0x85, 0xbd, 0x70,
	0xd8, 0x9a, 0x44, 0x87, 0xd7, 0xdf, 0xc1, 0xac, 0x25, 0xf1, 0xf1, 0x82, 0xe9, 0x4f, 0x52, 0xb3,
	0x89, 0x64, 0x5f, 0x3c, 0x5b, 0x01, 0xca, 0x48, 0x64, 0xd5, 0x1a, 0x58, 0xcd, 0x13, 0x8e, 0xd0,
	0x1e, 0x69, 0x1a, 0x28, 0x94, 0xbb, 0x34, 0xf2, 0xec, 0x27, 0xa5, 0x03, 0xd2, 0x11, 0x12, 0x63,
	0x81, 0xeb, 0x5c, 0x65, 0x60, 0x58, 0xdd, 0xab, 0xda, 0x42, 0xe2, 0xf4, 0x2a, 0xe8, 0x3f, 0xf2,
	0xbd, 0x0a, 0x6d, 0x62, 0x24, 0xd8, 0xd8, 0x1a, 0x95, 0x67, 0xc0, 0x88, 0x57, 0x77, 0x85, 0xc4,
	0xb9, 0xb3, 0x73, 0x27, 0xab, 0xe1, 0x79, 0x96, 0xd8, 0x25, 0x9a, 0x35, 0xfb, 0xea, 0x0f, 0xbf,
	0x51, 0x3a, 0x24, 0x9d, 0x54, 0x6d, 0xac, 0x51, 0x8b, 0xad, 0xad, 0x9e, 0xd8, 0xf0, 0xaa, 0x3b,
	0xe3, 0x56, 0xdc, 0xe5, 0xc0, 0x9a, 0x77, 0x2b, 0xee, 0x72, 0xa0, 0x9c, 0x34, 0xc4, 0x2a, 0xd1,
	0x1a, 0x32, 0xd6, 0xf2, 0xe4, 0x0d, 0xd2, 0xbf, 0xa4, 0x0d, 0xba, 0x88, 0x6f, 0x4d, 0xdb, 0x6b,
	0x08, 0xe8, 0x62, 0x7a, 0xcd, 0xfa, 0xa4, 0x93, 0x42, 0x0e, 0x3a, 0x05, 0x2d, 0x14, 0x6c, 0xd8,
	0xfe, 0xa1, 0x0a, 0x67, 0x77, 0x70, 0x32, 0x38, 0xbc, 0xf3, 0xe0, 0x50, 0xf2, 0xf0, 0x58, 0xf2,
	0xf0, 0x54, 0xf2, 0xf0, 0xad, 0xe4, 0xe1, 0xfe, 0xcc, 0x83, 0xe3, 0x99, 0x07, 0xa7, 0x33, 0x0f,
	0x9e, 0xea, 0xee, 0xb7, 0x3f, 0x02, 0x00, 0x00, 0xff, 0xff, 0x99, 0x18, 0x29, 0x4a, 0x11, 0x02,
	0x00, 0x00,
}

func (m *Info) Marshal() (dAtA []byte, err error) {
	size := m.Size()
	dAtA = make([]byte, size)
	n, err := m.MarshalTo(dAtA)
	if err != nil {
		return nil, err
	}
	return dAtA[:n], nil
}

func (m *Info) MarshalTo(dAtA []byte) (int, error) {
	var i int
	_ = i
	var l int
	_ = l
	dAtA[i] = 0xa
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.GoVersion)))
	i += copy(dAtA[i:], m.GoVersion)
	dAtA[i] = 0x12
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.Tag)))
	i += copy(dAtA[i:], m.Tag)
	dAtA[i] = 0x1a
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.Time)))
	i += copy(dAtA[i:], m.Time)
	dAtA[i] = 0x22
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.Revision)))
	i += copy(dAtA[i:], m.Revision)
	dAtA[i] = 0x2a
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.CgoCompiler)))
	i += copy(dAtA[i:], m.CgoCompiler)
	dAtA[i] = 0x32
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.Platform)))
	i += copy(dAtA[i:], m.Platform)
	dAtA[i] = 0x3a
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.Distribution)))
	i += copy(dAtA[i:], m.Distribution)
	dAtA[i] = 0x42
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.Type)))
	i += copy(dAtA[i:], m.Type)
	dAtA[i] = 0x4a
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.Channel)))
	i += copy(dAtA[i:], m.Channel)
	dAtA[i] = 0x52
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.CgoTargetTriple)))
	i += copy(dAtA[i:], m.CgoTargetTriple)
	dAtA[i] = 0x5a
	i++
	i = encodeVarintInfo(dAtA, i, uint64(len(m.EnvChannel)))
	i += copy(dAtA[i:], m.EnvChannel)
	if m.Dependencies != nil {
		dAtA[i] = 0x82
		i++
		dAtA[i] = 0xf1
		i++
		dAtA[i] = 0x4
		i++
		i = encodeVarintInfo(dAtA, i, uint64(len(*m.Dependencies)))
		i += copy(dAtA[i:], *m.Dependencies)
	}
	return i, nil
}

func encodeVarintInfo(dAtA []byte, offset int, v uint64) int {
	for v >= 1<<7 {
		dAtA[offset] = uint8(v&0x7f | 0x80)
		v >>= 7
		offset++
	}
	dAtA[offset] = uint8(v)
	return offset + 1
}
func (m *Info) Size() (n int) {
	if m == nil {
		return 0
	}
	var l int
	_ = l
	l = len(m.GoVersion)
	n += 1 + l + sovInfo(uint64(l))
	l = len(m.Tag)
	n += 1 + l + sovInfo(uint64(l))
	l = len(m.Time)
	n += 1 + l + sovInfo(uint64(l))
	l = len(m.Revision)
	n += 1 + l + sovInfo(uint64(l))
	l = len(m.CgoCompiler)
	n += 1 + l + sovInfo(uint64(l))
	l = len(m.Platform)
	n += 1 + l + sovInfo(uint64(l))
	l = len(m.Distribution)
	n += 1 + l + sovInfo(uint64(l))
	l = len(m.Type)
	n += 1 + l + sovInfo(uint64(l))
	l = len(m.Channel)
	n += 1 + l + sovInfo(uint64(l))
	l = len(m.CgoTargetTriple)
	n += 1 + l + sovInfo(uint64(l))
	l = len(m.EnvChannel)
	n += 1 + l + sovInfo(uint64(l))
	if m.Dependencies != nil {
		l = len(*m.Dependencies)
		n += 3 + l + sovInfo(uint64(l))
	}
	return n
}

func sovInfo(x uint64) (n int) {
	return (math_bits.Len64(x|1) + 6) / 7
}
func sozInfo(x uint64) (n int) {
	return sovInfo(uint64((x << 1) ^ uint64((int64(x) >> 63))))
}
func (m *Info) Unmarshal(dAtA []byte) error {
	l := len(dAtA)
	iNdEx := 0
	for iNdEx < l {
		preIndex := iNdEx
		var wire uint64
		for shift := uint(0); ; shift += 7 {
			if shift >= 64 {
				return ErrIntOverflowInfo
			}
			if iNdEx >= l {
				return io.ErrUnexpectedEOF
			}
			b := dAtA[iNdEx]
			iNdEx++
			wire |= uint64(b&0x7F) << shift
			if b < 0x80 {
				break
			}
		}
		fieldNum := int32(wire >> 3)
		wireType := int(wire & 0x7)
		if wireType == 4 {
			return fmt.Errorf("proto: Info: wiretype end group for non-group")
		}
		if fieldNum <= 0 {
			return fmt.Errorf("proto: Info: illegal tag %d (wire type %d)", fieldNum, wire)
		}
		switch fieldNum {
		case 1:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field GoVersion", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.GoVersion = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 2:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field Tag", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.Tag = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 3:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field Time", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.Time = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 4:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field Revision", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.Revision = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 5:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field CgoCompiler", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.CgoCompiler = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 6:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field Platform", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.Platform = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 7:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field Distribution", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.Distribution = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 8:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field Type", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.Type = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 9:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field Channel", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.Channel = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 10:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field CgoTargetTriple", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.CgoTargetTriple = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 11:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field EnvChannel", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.EnvChannel = string(dAtA[iNdEx:postIndex])
			iNdEx = postIndex
		case 10000:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field Dependencies", wireType)
			}
			var stringLen uint64
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				stringLen |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			intStringLen := int(stringLen)
			if intStringLen < 0 {
				return ErrInvalidLengthInfo
			}
			postIndex := iNdEx + intStringLen
			if postIndex < 0 {
				return ErrInvalidLengthInfo
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			s := string(dAtA[iNdEx:postIndex])
			m.Dependencies = &s
			iNdEx = postIndex
		default:
			iNdEx = preIndex
			skippy, err := skipInfo(dAtA[iNdEx:])
			if err != nil {
				return err
			}
			if skippy < 0 {
				return ErrInvalidLengthInfo
			}
			if (iNdEx + skippy) < 0 {
				return ErrInvalidLengthInfo
			}
			if (iNdEx + skippy) > l {
				return io.ErrUnexpectedEOF
			}
			iNdEx += skippy
		}
	}

	if iNdEx > l {
		return io.ErrUnexpectedEOF
	}
	return nil
}
func skipInfo(dAtA []byte) (n int, err error) {
	l := len(dAtA)
	iNdEx := 0
	for iNdEx < l {
		var wire uint64
		for shift := uint(0); ; shift += 7 {
			if shift >= 64 {
				return 0, ErrIntOverflowInfo
			}
			if iNdEx >= l {
				return 0, io.ErrUnexpectedEOF
			}
			b := dAtA[iNdEx]
			iNdEx++
			wire |= (uint64(b) & 0x7F) << shift
			if b < 0x80 {
				break
			}
		}
		wireType := int(wire & 0x7)
		switch wireType {
		case 0:
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return 0, ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return 0, io.ErrUnexpectedEOF
				}
				iNdEx++
				if dAtA[iNdEx-1] < 0x80 {
					break
				}
			}
			return iNdEx, nil
		case 1:
			iNdEx += 8
			return iNdEx, nil
		case 2:
			var length int
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return 0, ErrIntOverflowInfo
				}
				if iNdEx >= l {
					return 0, io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				length |= (int(b) & 0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			if length < 0 {
				return 0, ErrInvalidLengthInfo
			}
			iNdEx += length
			if iNdEx < 0 {
				return 0, ErrInvalidLengthInfo
			}
			return iNdEx, nil
		case 3:
			for {
				var innerWire uint64
				var start int = iNdEx
				for shift := uint(0); ; shift += 7 {
					if shift >= 64 {
						return 0, ErrIntOverflowInfo
					}
					if iNdEx >= l {
						return 0, io.ErrUnexpectedEOF
					}
					b := dAtA[iNdEx]
					iNdEx++
					innerWire |= (uint64(b) & 0x7F) << shift
					if b < 0x80 {
						break
					}
				}
				innerWireType := int(innerWire & 0x7)
				if innerWireType == 4 {
					break
				}
				next, err := skipInfo(dAtA[start:])
				if err != nil {
					return 0, err
				}
				iNdEx = start + next
				if iNdEx < 0 {
					return 0, ErrInvalidLengthInfo
				}
			}
			return iNdEx, nil
		case 4:
			return iNdEx, nil
		case 5:
			iNdEx += 4
			return iNdEx, nil
		default:
			return 0, fmt.Errorf("proto: illegal wireType %d", wireType)
		}
	}
	panic("unreachable")
}

var (
	ErrInvalidLengthInfo = fmt.Errorf("proto: negative length found during unmarshaling")
	ErrIntOverflowInfo   = fmt.Errorf("proto: integer overflow")
)
