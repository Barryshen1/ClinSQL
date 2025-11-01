WITH aki_dx AS (
  -- Identify AKI diagnoses and classify primary vs secondary
  SELECT
    subject_id,
    hadm_id,
    MIN(seq_num) AS min_aki_seq
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code LIKE '584%')
    OR (icd_version = 10 AND icd_code LIKE 'N17%')
  GROUP BY
    subject_id,
    hadm_id
),
aki_adm AS (
  -- Join to admissions + patients, filter age/gender, compute LOS and AKI type
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE
      WHEN adx.min_aki_seq = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS aki_type,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN aki_dx adx
      ON a.subject_id = adx.subject_id
      AND a.hadm_id = adx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    -- keep LOS 1–7 days
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
),
imaging_counts AS (
  -- Count CT/MRI studies per admission
  SELECT
    ha.hadm_id,
    COUNT(he.hcpcs_cd) AS imaging_count
  FROM
    aki_adm ha
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
      ON ha.subject_id = he.subject_id
      AND ha.hadm_id = he.hadm_id
      AND he.chartdate BETWEEN DATE(ha.admittime) AND DATE(ha.dischtime)
      AND (
        LOWER(he.short_description) LIKE '%ct%'
        OR LOWER(he.short_description) LIKE '%mr%'
      )
  GROUP BY
    ha.hadm_id
)
SELECT
  aa.aki_type,
  CASE
    WHEN aa.los_days BETWEEN 1 AND 4 THEN '1-4'
    ELSE '5-7'
  END AS los_group,
  COUNT(DISTINCT aa.subject_id) AS patient_count,
  ROUND(AVG(COALESCE(ic.imaging_count, 0)), 2) AS mean_imaging_per_admission
FROM
  aki_adm aa
  LEFT JOIN imaging_counts ic
    ON aa.hadm_id = ic.hadm_id
GROUP BY
  aa.aki_type,
  los_group
ORDER BY
  aa.aki_type,
  los_group;