WITH sepsis_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND (
      dicd.long_title LIKE '%sepsis%'
      OR d.icd_code IN ('A41.9', 'R65.20', 'R65.21', 'R65.22', 'R65.11', 'R65.12', 'R65.11', 'R65.12', 'R65.20', 'R65.21')
    )
),
peak_platelet AS (
  SELECT 
    sp.subject_id,
    MAX(le.valuenum) AS peak_platelet_count
  FROM sepsis_patients sp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sp.subject_id = le.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) IN ('platelet', 'platelets', 'plt', 'platelet count')
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.valuenum < 1000000  -- remove implausible values
  GROUP BY sp.subject_id
)
SELECT 
  PERCENTILE_CONT(peak_platelet_count, 0.75) OVER () AS p75_peak_platelet_count
FROM peak_platelet
LIMIT 1;