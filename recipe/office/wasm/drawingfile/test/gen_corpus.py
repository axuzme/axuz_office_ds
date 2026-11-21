#!/usr/bin/env python3
# office/wasm/drawingfile/test/gen_corpus.py — gera o corpus SINTETICO de PDFs (e um XPS) do teste do drawingfile.wasm.
#
# O QUE: escreve PDFs minimos a mao (sem dependencia): texto base-14, vetor (paths, dash, clip, shading, alpha), imagens
#   (RGB/gray/mascara), fonte TrueType EMBUTIDA (a que o --font apontar), formularios (AcroForm) e anotacoes, multipagina com
#   outline, e um XPS minimo. Deterministico (sem data, sem aleatorio): mesmo corpus em toda execucao.
# USO: python3 -I gen_corpus.py <dir-saida> [--font caminho.ttf]
# ONDE: test.sh (antes do harness). Nao usa rede.
import os, struct, sys, zlib, zipfile


class Pdf:
    """Montador de PDF: add(obj-bytes) devolve numero; save escreve xref/trailer. Onde: todos os geradores deste arquivo."""

    def __init__(self):
        self.objs = []

    def add(self, body):
        self.objs.append(body if isinstance(body, bytes) else body.encode("latin1"))
        return len(self.objs)

    def reserve(self):
        self.objs.append(None)
        return len(self.objs)

    def set(self, num, body):
        self.objs[num - 1] = body if isinstance(body, bytes) else body.encode("latin1")

    def stream(self, d, data, flate=True):
        if flate:
            data = zlib.compress(data, 9)
            d += " /Filter /FlateDecode"
        return self.add(("<< %s /Length %d >>\nstream\n" % (d, len(data))).encode("latin1") + data + b"\nendstream")

    def save(self, path, root):
        out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
        offs = []
        for i, o in enumerate(self.objs):
            offs.append(len(out))
            out += ("%d 0 obj\n" % (i + 1)).encode() + o + b"\nendobj\n"
        x = len(out)
        out += ("xref\n0 %d\n0000000000 65535 f \n" % (len(self.objs) + 1)).encode()
        for o in offs:
            out += ("%010d 00000 n \n" % o).encode()
        out += ("trailer\n<< /Size %d /Root %d 0 R /ID [<00112233445566778899aabbccddeeff><00112233445566778899aabbccddeeff>] >>\nstartxref\n%d\n%%%%EOF\n" % (len(self.objs) + 1, root, x)).encode()
        open(path, "wb").write(out)


def pages_tree(p, page_nums, extra=""):
    """O que: cria /Pages + /Catalog. Onde: cada gerador."""
    kids = " ".join("%d 0 R" % n for n in page_nums)
    pg = p.reserve()
    cat = p.add("<< /Type /Catalog /Pages %d 0 R %s >>" % (pg, extra))
    p.set(pg, "<< /Type /Pages /Kids [%s] /Count %d >>" % (kids, len(page_nums)))
    return pg, cat


def page(p, pages_ref, content, res, annots=""):
    """O que: pagina A4-ish 595x842 com conteudo e recursos. Onde: geradores."""
    c = p.stream("", content.encode("latin1") if isinstance(content, str) else content)
    return p.add("<< /Type /Page /Parent %d 0 R /MediaBox [0 0 595 842] /Contents %d 0 R /Resources %s %s >>" % (pages_ref, c, res, annots))


def text_base14(path):
    """O que: texto nas 14 fontes base, tamanhos, cor, rotacao, render modes. Onde: corpus 'text-base14'."""
    p = Pdf()
    pgs = p.reserve()
    fonts = {}
    names = ["Helvetica", "Helvetica-Bold", "Times-Roman", "Times-Italic", "Courier", "Courier-Bold", "Symbol", "ZapfDingbats"]
    for i, n in enumerate(names):
        fonts["F%d" % i] = p.add("<< /Type /Font /Subtype /Type1 /BaseFont /%s >>" % n)
    res = "<< /Font << %s >> >>" % " ".join("/%s %d 0 R" % (k, v) for k, v in fonts.items())
    nums = []
    for pg in range(2):
        c = ""
        for i in range(len(names)):
            c += "BT /F%d %d Tf 50 %d Td (Axuz %s pagina %d: The quick brown fox 0123456789 ÁÉ) Tj ET\n" % (i, 12 + i, 780 - i * 40, names[i], pg + 1)
        c += "0.8 0.1 0.1 rg BT /F1 24 Tf 1 0 0.3 1 50 400 Tm (Texto cor e inclinacao) Tj ET\n"
        c += "BT /F2 30 Tf 1 Tr 0 0 1 RG 50 300 Td (Contorno) Tj ET\n"
        c += "BT /F0 14 Tf 0.707 0.707 -0.707 0.707 300 100 Tm 2 Tc 5 Tw (Rotacionado com espacamento) Tj ET\n"
        nums.append(page(p, pgs, c, res))
    p.set(pgs, "<< /Type /Pages /Kids [%s] /Count 2 >>" % " ".join("%d 0 R" % n for n in nums))
    root = p.add("<< /Type /Catalog /Pages %d 0 R >>" % pgs)
    p.save(path, root)


def vector(path):
    """O que: paths, dash, joins, clip, shading axial/radial, transparencia (ExtGState), padrao. Onde: corpus 'vector'."""
    p = Pdf()
    sh = p.add("<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [50 0 250 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> /Extend [true true] >>")
    sh2 = p.add("<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [400 600 0 400 600 80] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 1 0] /C1 [0 0.5 0] /N 1 >> /Extend [false false] >>")
    res = "<< /Shading << /S1 %d 0 R /S2 %d 0 R >> /ExtGState << /G1 << /ca 0.4 /CA 0.4 >> >> >>" % (sh, sh2)
    c = ("q 2 w 1 J 1 j [6 3] 0 d 0 0.5 0 RG 50 700 m 150 780 250 780 350 700 c S Q\n"
         "q 0.9 0.9 0.2 rg 0 0 0 RG 4 w 50 600 120 60 re B Q\n"
         "q 50 450 200 100 re W n /S1 sh Q\n"
         "q 340 520 120 120 re W n /S2 sh Q\n"
         "q 1 0 0 rg 300 300 100 100 re f /G1 gs 0 0 1 rg 350 350 100 100 re f Q\n"
         "q 0.2 w 0.3 0.3 0.3 RG 0 0 m 595 842 l S 595 0 m 0 842 l S Q\n"
         "q 5 w 0 0 0 RG 1 0 0 1 100 150 cm 0 0 m 100 0 l 100 100 l h S Q\n"
         "q 0.5 g 400 100 m 450 180 l 500 100 l 420 140 l 480 140 l h f* Q\n")
    pgs = p.reserve()
    n = page(p, pgs, c, res)
    p.set(pgs, "<< /Type /Pages /Kids [%d 0 R] /Count 1 >>" % n)
    p.save(path, p.add("<< /Type /Catalog /Pages %d 0 R >>" % pgs))


def images(path):
    """O que: imagens RGB 8bpc, gray, mascara 1bpc e SMask; nao usa JPEG (sem codec local). Onde: corpus 'images'."""
    p = Pdf()
    w, h = 64, 48
    rgb = bytearray()
    for y in range(h):
        for x in range(w):
            rgb += bytes(((x * 4) % 256, (y * 5) % 256, ((x + y) * 3) % 256))
    i1 = p.stream("/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8" % (w, h), bytes(rgb))
    gray = bytes(((x ^ y) * 4) % 256 for y in range(h) for x in range(w))
    i2 = p.stream("/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceGray /BitsPerComponent 8" % (w, h), gray)
    sm = p.stream("/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceGray /BitsPerComponent 8" % (w, h), bytes(((x * 4) % 256) for y in range(h) for x in range(w)))
    i3 = p.stream("/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask %d 0 R" % (w, h, sm), bytes(rgb))
    mk = p.stream("/Type /XObject /Subtype /Image /Width 16 /Height 16 /ImageMask true /BitsPerComponent 1", bytes([0xAA, 0x55] * 16))
    idx = p.stream("/Type /XObject /Subtype /Image /Width 8 /Height 8 /ColorSpace [/Indexed /DeviceRGB 3 <ff0000 00ff00 0000ff ffff00>] /BitsPerComponent 2", bytes([0b00011011] * 2 + [0b11100100] * 2) * 4)
    res = "<< /XObject << /I1 %d 0 R /I2 %d 0 R /I3 %d 0 R /IM %d 0 R /IX %d 0 R >> >>" % (i1, i2, i3, mk, idx)
    c = ("q 200 0 0 150 50 650 cm /I1 Do Q\nq 200 0 0 150 300 650 cm /I2 Do Q\n"
         "0.9 0.9 0.5 rg 50 400 300 150 re f q 250 0 0 120 60 415 cm /I3 Do Q\n"
         "q 1 0 0 rg 100 0 0 100 400 420 cm /IM Do Q\nq 80 0 0 80 50 250 cm /IX Do Q\n"
         "q 0.7 0.7 -0.7 0.7 350 200 cm 120 0 0 90 0 0 cm /I1 Do Q\n")
    pgs = p.reserve()
    n = page(p, pgs, c, res)
    p.set(pgs, "<< /Type /Pages /Kids [%d 0 R] /Count 1 >>" % n)
    p.save(path, p.add("<< /Type /Catalog /Pages %d 0 R >>" % pgs))


def embedded_font(path, ttf):
    """O que: TrueType embutida (FontFile2, WinAnsi) com texto + CIDFontType2 Identity-H. Onde: corpus 'embedded-font'."""
    data = open(ttf, "rb").read()
    p = Pdf()
    ff = p.stream("/Length1 %d" % len(data), data)
    desc = p.add("<< /Type /FontDescriptor /FontName /AAAAAA+Narrow /Flags 32 /FontBBox [-200 -250 1000 900] /ItalicAngle 0 /Ascent 900 /Descent -250 /CapHeight 700 /StemV 80 /FontFile2 %d 0 R >>" % ff)
    widths = " ".join(["500"] * 224)
    f1 = p.add("<< /Type /Font /Subtype /TrueType /BaseFont /AAAAAA+Narrow /FirstChar 32 /LastChar 255 /Widths [%s] /Encoding /WinAnsiEncoding /FontDescriptor %d 0 R >>" % (widths, desc))
    cid = p.add("<< /Type /Font /Subtype /CIDFontType2 /BaseFont /AAAAAA+Narrow /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor %d 0 R /DW 500 /CIDToGIDMap /Identity >>" % desc)
    f2 = p.add("<< /Type /Font /Subtype /Type0 /BaseFont /AAAAAA+Narrow /Encoding /Identity-H /DescendantFonts [%d 0 R] >>" % cid)
    res = "<< /Font << /E1 %d 0 R /E2 %d 0 R >> >>" % (f1, f2)
    gids = "".join("%04X" % g for g in range(36, 76))
    c = ("BT /E1 18 Tf 50 780 Td (Fonte TrueType embutida: texto ASCII e acentuacao) Tj 0 -30 Td 0 0 1 rg (Segunda linha em azul 1234567890) Tj ET\n"
         "BT /E2 20 Tf 50 650 Td <%s> Tj ET\nBT /E1 9 Tf 50 600 Td (Linha pequena: lorem ipsum dolor sit amet, consectetur) Tj ET\n" % gids)
    pgs = p.reserve()
    n = page(p, pgs, c, res)
    p.set(pgs, "<< /Type /Pages /Kids [%d 0 R] /Count 1 >>" % n)
    p.save(path, p.add("<< /Type /Catalog /Pages %d 0 R >>" % pgs))


def forms_annots(path):
    """O que: AcroForm (texto com AP, checkbox, combo) + anotacoes (Link URI/GoTo, Highlight, Text, Square com AP, FreeText).
    Onde: corpus 'forms-annots'."""
    p = Pdf()
    helv = p.add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    pgs = p.reserve()
    page_obj = p.reserve()
    ap_t = p.stream("/Type /XObject /Subtype /Form /BBox [0 0 200 24] /Resources << /Font << /Helv %d 0 R >> >>" % helv, b"/Tx BMC q BT /Helv 12 Tf 0 g 3 7 Td (Valor inicial) Tj ET Q EMC")
    tf = p.add("<< /Type /Annot /Subtype /Widget /FT /Tx /T (nome) /V (Valor inicial) /DA (/Helv 12 Tf 0 g) /Rect [50 700 250 724] /F 4 /P %d 0 R /AP << /N %d 0 R >> /MK << /BC [0 0 0] /BG [0.95 0.95 0.95] >> >>" % (page_obj, ap_t))
    on = p.stream("/Type /XObject /Subtype /Form /BBox [0 0 16 16]", b"0 g 2 2 12 12 re f")
    off = p.stream("/Type /XObject /Subtype /Form /BBox [0 0 16 16]", b"0.5 G 2 2 12 12 re S")
    cb = p.add("<< /Type /Annot /Subtype /Widget /FT /Btn /T (aceito) /V /Yes /AS /Yes /Rect [50 650 66 666] /F 4 /P %d 0 R /AP << /N << /Yes %d 0 R /Off %d 0 R >> >> /MK << /CA (4) >> >>" % (page_obj, on, off))
    cmb = p.add("<< /Type /Annot /Subtype /Widget /FT /Ch /Ff 131072 /T (opcao) /V (B) /Opt [(A) (B) (C)] /DA (/Helv 12 Tf 0 g) /Rect [50 600 200 620] /F 4 /P %d 0 R >>" % page_obj)
    link = p.add("<< /Type /Annot /Subtype /Link /Rect [50 540 200 560] /Border [0 0 1] /A << /S /URI /URI (https://example.com/) >> >>")
    glink = p.add("<< /Type /Annot /Subtype /Link /Rect [50 510 200 530] /Border [0 0 1] /Dest [%d 0 R /XYZ 0 800 0] >>" % page_obj)
    hl = p.add("<< /Type /Annot /Subtype /Highlight /Rect [50 470 250 490] /QuadPoints [50 490 250 490 50 470 250 470] /C [1 1 0] /F 4 /Contents (realce) >>")
    note = p.add("<< /Type /Annot /Subtype /Text /Rect [300 700 320 720] /Contents (Nota de teste) /Name /Comment /C [1 0.8 0] /F 28 >>")
    sq_ap = p.stream("/Type /XObject /Subtype /Form /BBox [0 0 100 60]", b"1 0 0 RG 3 w 2 2 96 56 re S")
    sq = p.add("<< /Type /Annot /Subtype /Square /Rect [300 600 400 660] /C [1 0 0] /F 4 /BS << /W 3 >> /AP << /N %d 0 R >> >>" % sq_ap)
    ft = p.add("<< /Type /Annot /Subtype /FreeText /Rect [300 520 450 560] /DA (/Helv 12 Tf 0 0 1 rg) /Contents (Texto livre) /F 4 >>")
    annots = [tf, cb, cmb, link, glink, hl, note, sq, ft]
    fields = [tf, cb, cmb]
    p.set(page_obj, "<< /Type /Page /Parent %d 0 R /MediaBox [0 0 595 842] /Contents %d 0 R /Resources << /Font << /Helv %d 0 R >> >> /Annots [%s] >>" % (pgs, p.stream("", b"BT /Helv 14 Tf 50 760 Td (Formulario e anotacoes) Tj ET BT /Helv 10 Tf 50 735 Td (Nome:) Tj 70 -50 Td (Aceito) Tj ET"), helv, " ".join("%d 0 R" % a for a in annots)))
    p.set(pgs, "<< /Type /Pages /Kids [%d 0 R] /Count 1 >>" % page_obj)
    root = p.add("<< /Type /Catalog /Pages %d 0 R /AcroForm << /Fields [%s] /DA (/Helv 0 Tf 0 g) /DR << /Font << /Helv %d 0 R >> >> /NeedAppearances false >> >>" % (pgs, " ".join("%d 0 R" % f for f in fields), helv))
    p.save(path, root)


def multipage_outline(path):
    """O que: 12 paginas, tamanhos/rotacoes diferentes, outline em dois niveis, rotulos. Onde: corpus 'multipage-outline'."""
    p = Pdf()
    helv = p.add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    pgs = p.reserve()
    nums = []
    sizes = [(595, 842), (842, 595), (612, 792), (300, 400)]
    for i in range(12):
        w, h = sizes[i % 4]
        rot = (i % 3) * 90 if i % 5 == 0 else 0
        c = p.stream("", ("BT /F1 28 Tf 30 %d Td (Pagina %d) Tj ET 0.%d g 20 20 %d %d re f" % (h - 60, i + 1, i % 9, 40 + i * 10, 20 + i * 5)).encode())
        nums.append(p.add("<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %d %d] /Rotate %d /Contents %d 0 R /Resources << /Font << /F1 %d 0 R >> >> >>" % (pgs, w, h, rot, c, helv)))
    p.set(pgs, "<< /Type /Pages /Kids [%s] /Count %d >>" % (" ".join("%d 0 R" % n for n in nums), len(nums)))
    o_root = p.reserve()
    o1 = p.reserve(); o2 = p.reserve(); o3 = p.reserve()
    p.set(o1, "<< /Title (Capitulo 1) /Parent %d 0 R /Next %d 0 R /First %d 0 R /Last %d 0 R /Count 1 /Dest [%d 0 R /XYZ 0 800 0] >>" % (o_root, o2, o3, o3, nums[0]))
    p.set(o3, "<< /Title (Secao 1.1) /Parent %d 0 R /Dest [%d 0 R /Fit] >>" % (o1, nums[2]))
    p.set(o2, "<< /Title (Capitulo 2) /Parent %d 0 R /Prev %d 0 R /Dest [%d 0 R /Fit] >>" % (o_root, o1, nums[6]))
    p.set(o_root, "<< /Type /Outlines /First %d 0 R /Last %d 0 R /Count 3 >>" % (o1, o2))
    root = p.add("<< /Type /Catalog /Pages %d 0 R /Outlines %d 0 R /PageMode /UseOutlines /PageLabels << /Nums [0 << /S /r >> 4 << /S /D /St 1 >>] >> >>" % (pgs, o_root))
    p.save(path, root)


def xps_min(path):
    """O que: XPS minimo (FixedDocumentSequence/FixedDocument/FixedPage com path e glyph-less). Onde: corpus 'min.xps'."""
    page = ('<?xml version="1.0" encoding="utf-8"?><FixedPage xmlns="http://schemas.microsoft.com/xps/2005/06" Width="816" Height="1056" xml:lang="en-US">'
            '<Path Data="M 50,50 L 300,50 L 300,200 L 50,200 Z" Fill="#FF2080C0" Stroke="#FF000000" StrokeThickness="4"/>'
            '<Path Data="M 100,300 C 200,250 300,350 400,300" Stroke="#FFCC0000" StrokeThickness="6"/></FixedPage>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        def w(n, s):
            zi = zipfile.ZipInfo(n, (2020, 1, 1, 0, 0, 0)); zi.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(zi, s)
        w("[Content_Types].xml", '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="fdseq" ContentType="application/vnd.ms-package.xps-fixeddocumentsequence+xml"/><Default Extension="fdoc" ContentType="application/vnd.ms-package.xps-fixeddocument+xml"/><Default Extension="fpage" ContentType="application/vnd.ms-package.xps-fixedpage+xml"/></Types>')
        w("_rels/.rels", '<?xml version="1.0" encoding="utf-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="R0" Type="http://schemas.microsoft.com/xps/2005/06/fixedrepresentation" Target="/FixedDocumentSequence.fdseq"/></Relationships>')
        w("FixedDocumentSequence.fdseq", '<?xml version="1.0" encoding="utf-8"?><FixedDocumentSequence xmlns="http://schemas.microsoft.com/xps/2005/06"><DocumentReference Source="/Documents/1/FixedDocument.fdoc"/></FixedDocumentSequence>')
        w("Documents/1/FixedDocument.fdoc", '<?xml version="1.0" encoding="utf-8"?><FixedDocument xmlns="http://schemas.microsoft.com/xps/2005/06"><PageContent Source="Pages/1.fpage"/></FixedDocument>')
        w("Documents/1/Pages/1.fpage", page)


def main():
    """O que: gera todo o corpus em <saida>. Onde: linha de comando."""
    out = sys.argv[1]
    font = None
    if "--font" in sys.argv:
        font = sys.argv[sys.argv.index("--font") + 1]
    os.makedirs(out, exist_ok=True)
    text_base14(out + "/text-base14.pdf")
    vector(out + "/vector.pdf")
    images(out + "/images.pdf")
    if font:
        embedded_font(out + "/embedded-font.pdf", font)
    forms_annots(out + "/forms-annots.pdf")
    multipage_outline(out + "/multipage-outline.pdf")
    xps_min(out + "/min.xps")
    print("corpus em", out, sorted(os.listdir(out)))


if __name__ == "__main__":
    main()
