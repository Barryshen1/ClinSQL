WITH chest_pain_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
     AND d.seq_num    = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND LOWER(dd.long_title) LIKE '%chest pain%'
),
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS first_val,
    le.ref_range_upper AS upper_ref
  FROM (
    SELECT
      le.*,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` le
      JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
        ON le.itemid = di.itemid
    WHERE
      -- filter for high-sensitivity Troponin T
      LOWER(di.label) LIKE '%troponin t%'
      AND LOWER(di.label) LIKE '%high sensitivity%'
      AND le.valuenum IS NOT NULL
  ) le
  WHERE
    le.rn = 1
),
elevated_trop AS (
  SELECT
    c.hadm_id,
    f.first_val,
    c.hospital_expire_flag
  FROM
    chest_pain_adms c
    JOIN first_troponin f
      ON c.hadm_id = f.hadm_id
  WHERE
    f.first_val > CAST(f.upper_ref AS FLOAT64)
)
SELECT
  COUNT(*) AS n_admissions,
  ROUND(AVG(first_val), 2) AS mean_troponin,
  APPROX_QUANTILES(first_val, 2)[OFFSET(1)] AS median_troponin,
  ROUND(  SUM(hospital_expire_flag) * 1.0 / COUNT(*) , 3) AS mortality_rate
FROM
  elevated_trop;