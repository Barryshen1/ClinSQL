WITH first_icustays AS (
  -- pick each subject's first ICU stay (earliest intime)
  SELECT * EXCEPT (rn)
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),

male_age_filtered AS (
  -- male patients aged 51-61 (anchor_age is age capped at 89)
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),

-- select subjects whose first ICU stay is on an admission that has any pneumonia diagnosis
pneumonia_first_icu AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.los
  FROM first_icustays f
  JOIN male_age_filtered p
    ON f.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.subject_id = a.subject_id
   AND f.hadm_id = a.hadm_id
  WHERE f.los IS NOT NULL
    AND f.los >= 0
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = f.hadm_id
        AND LOWER(dd.long_title) LIKE '%pneumonia%'
    )
)

SELECT
  -- approximate 25th percentile of first-ICU LOS (days)
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile_days,
  COUNT(*) AS n_subjects_in_group
FROM (
  -- ensure one row per subject (distinct subject + their first ICU LOS)
  SELECT DISTINCT subject_id, los
  FROM pneumonia_first_icu
);