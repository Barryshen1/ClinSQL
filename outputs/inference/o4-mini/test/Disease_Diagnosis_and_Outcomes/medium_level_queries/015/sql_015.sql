WITH stroke_admissions AS (
  -- 1. Identify female 48–58 y/o stroke admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND LOWER(dd.long_title) LIKE '%stroke%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
),

comorbidity_counts AS (
  -- 2. Count distinct non-stroke diagnoses per admission
  SELECT
    d.subject_id,
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) 
      - COUNT(DISTINCT CASE 
          WHEN LOWER(dd.long_title) LIKE '%stroke%' THEN d.icd_code 
          ELSE NULL END
        ) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    EXISTS (
      SELECT 1
      FROM stroke_admissions sa
      WHERE sa.subject_id = d.subject_id
        AND sa.hadm_id = d.hadm_id
    )
  GROUP BY
    d.subject_id,
    d.hadm_id
),

burden_tertiles AS (
  -- 3. Assign Low/Medium/High comorbidity burden via tertiles
  SELECT
    cc.*,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS tertile
  FROM
    comorbidity_counts cc
),

burden_categories AS (
  SELECT
    subject_id,
    hadm_id,
    comorbidity_count,
    CASE tertile
      WHEN 1 THEN 'Low'
      WHEN 2 THEN 'Medium'
      WHEN 3 THEN 'High'
    END AS burden_cat
  FROM
    burden_tertiles
),

icustay_flags AS (
  -- 4. Flag ICU vs non-ICU
  SELECT
    subject_id,
    hadm_id,
    1 AS icu_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY
    subject_id,
    hadm_id
)

SELECT
  -- grouping variables
  IFNULL(icf.icu_flag, 0) AS is_icu,                -- 1 = ICU, 0 = non-ICU
  CASE
    WHEN DATE_DIFF(sa.dischtime, sa.admittime, DAY) <= 5 THEN '≤5'
    ELSE '>5'
  END AS los_cat,
  bc.burden_cat,

  -- counts and rate
  COUNT(*)                        AS n_admissions,
  SUM(sa.hospital_expire_flag)    AS n_deaths,
  SAFE_DIVIDE(SUM(sa.hospital_expire_flag), COUNT(*)) AS mortality_rate,

  -- 95% Wald confidence interval
  (
    SAFE_DIVIDE(SUM(sa.hospital_expire_flag), COUNT(*))
    - 1.96 * SQRT(
        SAFE_DIVIDE(SUM(sa.hospital_expire_flag), COUNT(*))
        * (1 - SAFE_DIVIDE(SUM(sa.hospital_expire_flag), COUNT(*)))
        / COUNT(*)
      )
  ) AS ci_lower,
  (
    SAFE_DIVIDE(SUM(sa.hospital_expire_flag), COUNT(*))
    + 1.96 * SQRT(
        SAFE_DIVIDE(SUM(sa.hospital_expire_flag), COUNT(*))
        * (1 - SAFE_DIVIDE(SUM(sa.hospital_expire_flag), COUNT(*)))
        / COUNT(*)
      )
  ) AS ci_upper

FROM
  stroke_admissions sa
  -- comorbidity category
  JOIN burden_categories bc
    ON sa.subject_id = bc.subject_id
    AND sa.hadm_id = bc.hadm_id
  -- ICU flag (left join to catch non-ICU)
  LEFT JOIN icustay_flags icf
    ON sa.subject_id = icf.subject_id
    AND sa.hadm_id = icf.hadm_id

GROUP BY
  is_icu,
  los_cat,
  bc.burden_cat

ORDER BY
  is_icu DESC,
  los_cat,
  bc.burden_cat;