WITH 
-- ... (rest of the CTEs remain the same)

-- Combine and calculate statistics
SELECT 
  COUNT(DISTINCT pa.subject_id) AS patient_count,
  COUNT(DISTINCT pa.hadm_id) AS admission_count,
  AVG(fht.valuenum) AS hs_tnt_mean,
  APPROX_QUANTILES(fht.valuenum, ARRAY< FLOAT64 >[0.5])[OFFSET(1)] AS hs_tnt_median,
  APPROX_QUANTILES(fht.valuenum, ARRAY< FLOAT64 >[0.25])[OFFSET(1)] AS hs_tnt_q1,
  APPROX_QUANTILES(fht.valuenum, ARRAY< FLOAT64 >[0.75])[OFFSET(1)] AS hs_tnt_q3,
  APPROX_QUANTILES(fht.valuenum, ARRAY< FLOAT64 >[0.75])[OFFSET(1)] - 
  APPROX_QUANTILES(fht.valuenum, ARRAY< FLOAT64 >[0.25])[OFFSET(1)] AS hs_tnt_iqr
FROM 
  patients_admissions pa
JOIN 
  ami_admissions aa 
  ON pa.subject_id = aa.subject_id AND pa.hadm_id = aa.hadm_id
JOIN 
  first_hs_tnt fht 
  ON pa.subject_id = fht.subject_id AND pa.hadm_id = fht.hadm_id
WHERE 
  fht.charttime < pa.admittime + INTERVAL 1 DAY;