WITH first_admissions AS (
  SELECT subject_id, hadm_id, admittime
  FROM (
    SELECT subject_id, hadm_id, admittime,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    WHERE hadm_id IS NOT NULL
  )
  WHERE rn = 1
),
first_icu_stays AS (
  SELECT fa.subject_id, fa.hadm_id, fis.stay_id, fis.los
  FROM first_admissions fa
  INNER JOIN (
    SELECT hadm_id, stay_id, los, intime,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) fis ON fa.hadm_id = fis.hadm_id AND fis.rn = 1
),
pneumonia_cohort AS (
  SELECT fis.subject_id, fis.hadm_id, fis.stay_id, fis.los
  FROM first_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON fis.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 51
    AND p.anchor_age <= 61
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = fis.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'J18%')
          OR
          (d.icd_version = 9 AND d.icd_code = '486')
        )
    )
)
SELECT APPROX_QUANTILES(los, 4)[OFFSET(1)] AS p25_los_days
FROM pneumonia_cohort;