WHERE 
  le.charttime >= a.admittime 
  AND le.charttime <= a.admittime + INTERVAL '48 hours'
  AND le.valuenum IS NOT NULL
  AND le.ref_range_lower IS NOT NULL 
  AND le.ref_range_upper IS NOT NULL
  AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper);