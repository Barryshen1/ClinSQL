WITH hemorrhagic_stroke_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
    JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      -- ICD-10 hemorrhagic stroke
      (d.icd_version = 10 AND (
        LEFT(d.icd_code, 3) IN ('I60', 'I61', 'I62')
      ))
      -- ICD-9 hemorrhagic stroke
      OR (d.icd_version = 9 AND (
        LEFT(d.icd_code, 3) IN ('430', '431', '432')
      ))
    )
),
admission_max_icu_stay AS (
  -- For each admission, get the longest ICU stay in days
  SELECT
    i.hadm_id,
    MAX(TIMESTAMP_DIFF(i.outtime, i.intime, DAY)) AS icu_stay_days
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  GROUP BY
    i.hadm_id
),
ultrasound_counts AS (
  -- Count ultrasound procedures per admission
  SELECT
    pr.hadm_id,
    COUNTIF(
      -- ICD-9 ultrasound procedures: codes starting with '88'
      pr.icd_version = 9 AND LEFT(pr.icd_code, 2) = '88'
    ) AS ultrasound_count
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd pr
  GROUP BY
    pr.hadm_id
),
final_cohort AS (
  SELECT
    hsa.subject_id,
    hsa.hadm_id,
    ams.icu_stay_days,
    COALESCE(uc.ultrasound_count, 0) AS ultrasound_count,
    CASE
      WHEN ams.icu_stay_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN ams.icu_stay_days BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS stay_category
  FROM
    hemorrhagic_stroke_admissions hsa
    JOIN admission_max_icu_stay ams ON hsa.hadm_id = ams.hadm_id
    LEFT JOIN ultrasound_counts uc ON hsa.hadm_id = uc.hadm_id
  WHERE
    ams.icu_stay_days BETWEEN 1 AND 7
)
SELECT
  stay_category,
  COUNT(*) AS num_admissions,
  AVG(ultrasound_count) AS mean_ultrasounds_per_admission,
  MIN(ultrasound_count) AS min_ultrasounds_per_admission,
  MAX(ultrasound_count) AS max_ultrasounds_per_admission
FROM
  final_cohort
WHERE
  stay_category IS NOT NULL
GROUP BY
  stay_category
ORDER BY
  stay_category
;