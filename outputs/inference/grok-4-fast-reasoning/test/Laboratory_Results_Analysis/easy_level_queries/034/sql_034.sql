WITH qualifying_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 65
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
first_na AS (
  SELECT qa.hadm_id, l.valuenum
  FROM qualifying_admissions qa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON l.subject_id = qa.subject_id 
    AND l.hadm_id = qa.hadm_id
  WHERE l.itemid = 220645
    AND l.charttime >= qa.admittime
    AND l.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY qa.hadm_id ORDER BY l.charttime ASC) = 1
)
SELECT MIN(valuenum) AS min_admission_sodium
FROM first_na;