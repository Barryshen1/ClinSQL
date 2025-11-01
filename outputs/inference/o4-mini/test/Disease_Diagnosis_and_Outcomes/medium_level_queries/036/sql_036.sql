WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_hf
      ON a.hadm_id = d_hf.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd_hf
      ON d_hf.icd_code = dicd_hf.icd_code
         AND d_hf.icd_version = dicd_hf.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND d_hf.icd_code LIKE 'I50%'    -- Heart failure ICD‐10
),
comorbid_counts AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorb_count
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
  WHERE
    d.icd_code NOT LIKE 'I50%'     -- Exclude HF itself
  GROUP BY
    c.hadm_id
),
quantiles AS (
  SELECT
    APPROX_QUANTILES(comorb_count, 3) AS qs
  FROM
    comorbid_counts
),
with_tertile AS (
  SELECT
    cc.hadm_id,
    cc.comorb_count,
    CASE
      WHEN cc.comorb_count <= q.qs[OFFSET(1)] THEN 'Low'
      WHEN cc.comorb_count <= q.qs[OFFSET(2)] THEN 'Med'
      ELSE 'High'
    END AS comorb_tertile
  FROM
    comorbid_counts cc,
    quantiles q
),
flags AS (
  SELECT
    c.*,
    w.comorb_tertile,
    DATE_DIFF(CAST(c.dischtime AS DATE), CAST(c.admittime AS DATE), DAY) AS los_days,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_ckd
      WHERE d_ckd.hadm_id = c.hadm_id
        AND d_ckd.icd_code LIKE 'N18%'
    ) THEN 1 ELSE 0 END AS ckd_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_dm
      WHERE d_dm.hadm_id = c.hadm_id
        AND (
          d_dm.icd_code LIKE 'E10%' OR
          d_dm.icd_code LIKE 'E11%' OR
          d_dm.icd_code LIKE 'E12%' OR
          d_dm.icd_code LIKE 'E13%' OR
          d_dm.icd_code LIKE 'E14%'
        )
    ) THEN 1 ELSE 0 END AS diabetes_flag
  FROM
    cohort c
    JOIN with_tertile w
      ON c.hadm_id = w.hadm_id
),
final AS (
  SELECT
    CASE WHEN los_days <= 5 THEN '≤5' ELSE '>5' END AS los_group,
    comorb_tertile,
    COUNT(*) AS N,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_pct,
    100.0 * SUM(ckd_flag) / COUNT(*) AS ckd_pct,
    100.0 * SUM(diabetes_flag) / COUNT(*) AS diabetes_pct
  FROM
    flags
  GROUP BY
    los_group,
    comorb_tertile
)
SELECT
  *,
  ROUND(mortality_pct,1) AS mortality_pct,
  ROUND(ckd_pct,1)        AS ckd_pct,
  ROUND(diabetes_pct,1)    AS diabetes_pct
FROM
  final
ORDER BY
  los_group,
  comorb_tertile;