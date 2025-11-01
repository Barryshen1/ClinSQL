WITH sepsis_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND (DATETIME_DIFF(a.admittime, DATETIME(DATE(p.anchor_year, 1, 1)), YEAR) + p.anchor_age) BETWEEN 71 AND 81
    AND (
      (di.icd_version = 9 AND di.icd_code IN ('99592', '0380', '0381', '0382', '0383', '0384', '0388', '0389'))
      OR
      (di.icd_version = 10 AND di.icd_code IN ('A400', 'A401', 'A402', 'A403', 'A408', 'A409', 'A410', 'A411', 'A412', 'A413', 'A414', 'A415', 'A418', 'A419', 'R6520', 'R6521'))
    )
),
platelet_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'platelet count'
),
platelet_first_24h AS (
  SELECT 
    sp.subject_id,
    AVG(le.valuenum) AS avg_platelet_24h
  FROM sepsis_patients sp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON sp.hadm_id = le.hadm_id
  JOIN platelet_items pi ON le.itemid = pi.itemid
  WHERE le.charttime >= sp.admittime
    AND le.charttime < DATETIME_ADD(sp.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
  GROUP BY sp.subject_id
)
SELECT 
  APPROX_QUANTILES(avg_platelet_24h, 1000)[OFFSET(500)] AS median_platelet_count
FROM platelet_first_24h;