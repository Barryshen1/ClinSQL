WITH sepsis_admissions AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 58 AND 68
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND (
          d.icd_code LIKE 'A40.%' 
          OR d.icd_code LIKE 'A41.%' 
          OR d.icd_code LIKE 'R65.2%'
        )
    )
)
SELECT 
  APPROX_QUANTILES(i.los, 100)[OFFSET(50)] AS median_icu_los
FROM sepsis_admissions sa
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
  ON sa.hadm_id = i.hadm_id;