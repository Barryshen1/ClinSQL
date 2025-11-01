WITH base_cohort AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (
          (d.icd_version = 10 AND d.icd_code IN ('R070','R071','R072','R073','R074'))
          OR
          (d.icd_version = 9 AND d.icd_code IN ('78650','78651','78652','78653','78654','78659'))
        )
    )
),
first_troponin AS (
  SELECT 
    hadm_id,
    valuenum,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid = 50341
)
SELECT
  COUNT(*) AS total_admissions,
  SUM(bc.hospital_expire_flag) AS deaths,
  AVG(bc.hospital_expire_flag) AS mortality_rate
FROM base_cohort bc
INNER JOIN first_troponin ft
  ON bc.hadm_id = ft.hadm_id
WHERE ft.rn = 1
  AND ft.valuenum > 14;