WITH female_dka_hadms AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON p.subject_id = d.subject_id
  WHERE p.gender = 'F'
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '2501%') OR
      (d.icd_version = 10 AND d.icd_code IN ('E1010', 'E1011', 'E1110', 'E1111', 'E1310', 'E1311'))
    )
),
peak_glucose AS (
  SELECT 
    l.hadm_id,
    MAX(l.valuenum) AS peak_glucose
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN female_dka_hadms f 
    ON l.hadm_id = f.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON l.hadm_id = a.hadm_id
  WHERE l.itemid = 50809
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
    AND l.charttime >= a.admittime
    AND l.charttime <= a.dischtime
  GROUP BY l.hadm_id
  HAVING COUNT(*) > 0
)
SELECT 
  APPROX_QUANTILES(pg.peak_glucose, 2)[OFFSET(1)] AS median_peak_glucose
FROM peak_glucose pg;