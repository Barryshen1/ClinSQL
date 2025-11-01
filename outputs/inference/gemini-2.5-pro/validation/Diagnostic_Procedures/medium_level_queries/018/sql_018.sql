WITH
  HemorrhagicStrokeAdmissions AS (
    SELECT DISTINCT
      adm.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 80 AND 90
      AND (
        -- ICD-9 codes for hemorrhagic stroke
        dx.icd_code IN ('430', '431', '432')
        -- ICD-10 codes for hemorrhagic stroke
        OR dx.icd_code LIKE 'I60%'
        OR dx.icd_code LIKE 'I61%'
        OR dx.icd_code LIKE 'I62%'
      )
  ),
  UltrasoundCounts AS (
    SELECT
      proc.hadm_id,
      COUNT(*) AS ultrasound_count
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
      ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
      LOWER(d_proc.long_title) LIKE '%ultrasound%'
    GROUP BY
      proc.hadm_id
  ),
  AdmissionsWithLOS AS (
    SELECT
      hsa.hadm_id,
      -- Calculate length of stay in days, rounding up. A stay of <24 hours is 1 day.
      CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS los_days,
      COALESCE(uc.ultrasound_count, 0) AS ultrasound_count
    FROM
      HemorrhagicStrokeAdmissions AS hsa
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON hsa.hadm_id = adm.hadm_id
    LEFT JOIN
      UltrasoundCounts AS uc
      ON hsa.hadm_id = uc.hadm_id
    WHERE
      adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
  )
SELECT
  los_category,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM
  (
    SELECT
      los_days,
      ultrasound_count,
      CASE
        WHEN los_days BETWEEN 1 AND 4
        THEN '1-4 day stay'
        WHEN los_days BETWEEN 5 AND 7
        THEN '5-7 day stay'
        ELSE 'Other'
      END AS los_category
    FROM
      AdmissionsWithLOS
  ) AS CategorizedAdmissions
WHERE
  los_category IN ('1-4 day stay', '5-7 day stay')
GROUP BY
  los_category
ORDER BY
  los_category;