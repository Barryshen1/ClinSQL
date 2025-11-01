WITH cohort AS (
  -- Select male patients aged 59-69
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),
hf_admissions AS (
  -- Admissions with heart failure diagnosis
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN cohort c ON adm.subject_id = c.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx ON adm.hadm_id = dx.hadm_id
  WHERE
    (
      (dx.icd_version = 9 AND dx.icd_code LIKE '428%') -- ICD-9 Heart Failure
      OR
      (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%') -- ICD-10 Heart Failure
    )
),
los_bins AS (
  -- Calculate LOS and bin
  SELECT
    ha.subject_id,
    ha.hadm_id,
    ha.admittime,
    ha.dischtime,
    DATETIME_DIFF(ha.dischtime, ha.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(ha.dischtime, ha.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATETIME_DIFF(ha.dischtime, ha.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_bin
  FROM
    hf_admissions ha
),
radiology_ct_codes AS (
  -- Get ICD procedure codes for radiography/CT
  SELECT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    (
      (icd_version = 9 AND (icd_code LIKE '87%' OR icd_code LIKE '88%')) -- 87: radiology, 88: CT/MRI
      OR
      (icd_version = 10 AND (icd_code LIKE 'B%' OR icd_code LIKE 'C%' OR icd_code LIKE 'D%')) -- Example: imaging codes in ICD-10-PCS
    )
),
rad_ct_counts AS (
  -- Count radiography/CT procedures per admission
  SELECT
    lb.subject_id,
    lb.hadm_id,
    lb.los_bin,
    COUNT(DISTINCT proc.icd_code) AS rad_ct_count
  FROM
    los_bins lb
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
      ON lb.hadm_id = proc.hadm_id
    LEFT JOIN radiology_ct_codes rc
      ON proc.icd_code = rc.icd_code AND proc.icd_version = rc.icd_version
  WHERE
    lb.los_bin IS NOT NULL
    AND rc.icd_code IS NOT NULL -- Only count procedures that match radiology/CT codes
  GROUP BY
    lb.subject_id, lb.hadm_id, lb.los_bin
),
icu_use AS (
  -- Determine ICU use per admission
  SELECT
    hadm_id,
    1 AS icu_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY
    hadm_id
),
final AS (
  -- Merge counts and ICU use
  SELECT
    r.subject_id,
    r.hadm_id,
    r.los_bin,
    IFNULL(r.rad_ct_count, 0) AS rad_ct_count,
    IF(i.icu_flag IS NULL, 'No ICU', 'ICU') AS icu_use
  FROM
    rad_ct_counts r
    LEFT JOIN icu_use i ON r.hadm_id = i.hadm_id
)
SELECT
  los_bin,
  icu_use,
  APPROX_QUANTILES(rad_ct_count, 4)[OFFSET(1)] AS pct_25,
  APPROX_QUANTILES(rad_ct_count, 4)[OFFSET(2)] AS pct_50,
  APPROX_QUANTILES(rad_ct_count, 4)[OFFSET(3)] AS pct_75,
  COUNT(*) AS n_admissions
FROM
  final
GROUP BY
  los_bin, icu_use
ORDER BY
  los_bin, icu_use;