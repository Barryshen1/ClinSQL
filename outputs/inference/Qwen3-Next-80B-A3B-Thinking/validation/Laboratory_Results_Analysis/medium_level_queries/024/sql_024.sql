WITH first_troponin AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE
    di.label LIKE '%troponin%t%'
    AND (di.label LIKE '%high sensitivity%' OR di.label LIKE '%hs%')
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
)
SELECT
  COUNT(*) AS total_patients,
  SUM(a.hospital_expire_flag) AS deaths,
  SUM(a.hospital_expire_flag) * 1.0 / COUNT(*) AS mortality_rate
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
  ON a.hadm_id = d_icd.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON d_icd.icd_code = d_diag.icd_code AND d_icd.icd_version = d_diag.icd_version
JOIN first_troponin ft
  ON a.hadm_id = ft.hadm_id AND ft.rn = 1
WHERE
  p.gender = 'M'
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 64 AND 74
  AND d_icd.seq_num = 1
  AND d_diag.long_title LIKE '%chest pain%'
  AND ft.valuenum > ft.ref_range_upper;