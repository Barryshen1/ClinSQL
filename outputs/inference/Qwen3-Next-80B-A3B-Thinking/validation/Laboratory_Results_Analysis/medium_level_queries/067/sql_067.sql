WITH first_troponin AS (
  SELECT 
    hadm_id,
    valuenum AS first_troponin,
    charttime
  FROM (
    SELECT 
      hadm_id,
      valuenum,
      charttime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid = 50911
      AND valuenum IS NOT NULL
  ) t
  WHERE rn = 1
)
SELECT 
  COUNT(*) AS admission_count,
  AVG(p.anchor_age) AS mean_age,
  AVG(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS mean_los,
  AVG(ft.first_troponin) AS mean_first_troponin,
  SUM(CASE WHEN adm.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON adm.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON adm.hadm_id = diag.hadm_id
JOIN first_troponin ft ON adm.hadm_id = ft.hadm_id
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 52 AND 62
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')
  )
  AND ft.first_troponin > 0.01;