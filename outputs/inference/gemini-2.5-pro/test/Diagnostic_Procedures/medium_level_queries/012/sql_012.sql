WITH
  -- Step 1: Identify male patients aged 35-45 with an ACS diagnosis
  acs_cohort AS (
    SELECT DISTINCT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON a.hadm_id = dx.hadm_id
    WHERE
      p.gender = 'M'
      AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 35 AND 45
      AND (
        -- ICD-9 codes for ACS
        (
          dx.icd_version = 9 AND (
            SUBSTR(dx.icd_code, 1, 3) = '410' -- Acute Myocardial Infarction
            OR dx.icd_code = '4111' -- Intermediate coronary syndrome (Unstable Angina)
          )
        )
        -- ICD-10 codes for ACS
        OR (
          dx.icd_version = 10 AND (
            SUBSTR(dx.icd_code, 1, 3) IN ('I21', 'I22') -- Acute and Subsequent Myocardial Infarction
            OR SUBSTR(dx.icd_code, 1, 4) = 'I200' -- Unstable Angina
            OR SUBSTR(dx.icd_code, 1, 3) = 'I24' -- Other acute ischemic heart diseases
          )
        )
      )
  ),
  -- Step 2: Calculate LOS and assign admissions to buckets
  los_admissions AS (
    SELECT
      subject_id,
      hadm_id,
      CASE
        WHEN (DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1) BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN (DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1) BETWEEN 4 AND 7 THEN '4-7 days'
        ELSE NULL
      END AS los_group
    FROM
      acs_cohort
    WHERE
      dischtime IS NOT NULL AND admittime IS NOT NULL
  ),
  -- Step 3: Count ultrasound/echocardiography procedures per admission
  ultrasound_counts AS (
    SELECT
      h.hadm_id,
      COUNT(h.hcpcs_cd) AS num_ultrasounds
    FROM
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d ON h.hcpcs_cd = d.code
    WHERE
      -- Filter for echocardiography procedures, which are a form of ultrasound
      LOWER(d.short_description) LIKE '%echo%'
      OR LOWER(d.long_description) LIKE '%echocardiography%'
    GROUP BY
      h.hadm_id
  )
-- Step 4: Final aggregation to get patient counts and mean procedures per LOS group
SELECT
  los.los_group,
  COUNT(DISTINCT los.subject_id) AS patient_count,
  AVG(COALESCE(uc.num_ultrasounds, 0)) AS mean_ultrasounds_per_admission
FROM
  los_admissions AS los
  LEFT JOIN ultrasound_counts AS uc ON los.hadm_id = uc.hadm_id
WHERE
  los.los_group IS NOT NULL -- Only include admissions in the specified LOS groups
GROUP BY
  los.los_group
ORDER BY
  los.los_group;