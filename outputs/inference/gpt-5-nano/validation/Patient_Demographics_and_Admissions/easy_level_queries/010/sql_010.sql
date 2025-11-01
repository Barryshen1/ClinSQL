WITH aki_cohort AS (
  SELECT i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  WHERE LOWER(p.gender) IN ('f', 'female')
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = i.subject_id
        AND di.hadm_id = i.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '584%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
        )
    )
)
SELECT PERCENTILE_CONT(los, 0.25) OVER() AS p25_los_days
FROM aki_cohort
LIMIT 1;