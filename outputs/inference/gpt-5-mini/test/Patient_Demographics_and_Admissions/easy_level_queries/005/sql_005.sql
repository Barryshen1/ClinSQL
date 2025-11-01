WITH first_icu AS (
  -- get each subject's first ICU stay
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),

dialysis_admissions AS (
  -- admissions that have an ICD procedure whose description mentions "dialysis"
  SELECT DISTINCT
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON p.icd_code = d.icd_code
      AND p.icd_version = d.icd_version
  WHERE
    LOWER(COALESCE(d.long_title, '')) LIKE '%dialysis%'
),

eligible_first_icus AS (
  -- join first ICU stays to patient demographics and dialysis admissions
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.los
  FROM
    first_icu f
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
      ON f.subject_id = pt.subject_id
    JOIN dialysis_admissions da
      ON f.hadm_id = da.hadm_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 77 AND 87
    AND f.los IS NOT NULL
)

-- compute quartiles and IQR
SELECT
  quartiles[OFFSET(1)] AS q1_los_days,
  quartiles[OFFSET(3)] AS q3_los_days,
  SAFE_SUBTRACT(quartiles[OFFSET(3)], quartiles[OFFSET(1)]) AS iqr_los_days,
  cnt AS n_patients
FROM (
  SELECT
    APPROX_QUANTILES(los, 4) AS quartiles,
    COUNT(*) AS cnt
  FROM
    eligible_first_icus
);