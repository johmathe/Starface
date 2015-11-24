import artists
print '<ImageNetStructure>'
print '<releaseData>fall2011</releaseData>'
for k, v in artists.ARTISTS.iteritems():
  print '<synset gloss=\"%s\" wnid=\"n%08d\" words=\"%s\"></synset>' % (v, k, v)
print '</ImageNetStructure>'
