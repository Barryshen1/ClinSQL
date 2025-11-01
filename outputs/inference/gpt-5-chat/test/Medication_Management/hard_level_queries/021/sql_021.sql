WITH dx_flags AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    -- Flags for each diagnosis category
    MAX(CASE WHEN (diag.icd_version = 9 AND diag.icd_code LIKE '2880%')
              OR (diag.icd_version = 10 AND diag.icd_code LIKE 'D70%')
             THEN 1 ELSE 0 END) AS neutropenia_flag,
    MAX(CASE WHEN (diag.icd_version = 9 AND diag.icd_code = '7806')
              OR (diag.icd_version = 10 AND diag.icd_code LIKE 'R50%')
             THEN 1 ELSE 0 END) AS fever_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id
   AND adm.hadm_id = diag.hadm_id
  GROUP BY adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender,
           adm.admittime, adm.dischtime, adm.hospital_expire_flag
),
cohort AS (
  SELECT
    *
  FROM dx_flags
  WHERE gender = 'M'
    AND anchor_age BETWEEN 41 AND 51
    AND neutropenia_flag = 1
    AND fever_flag = 1
),
med_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT p.drug) AS uniq_med_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id
   AND c.hadm_id = p.hadm_id
   AND p.starttime >= c.admittime
   AND p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_meds AS (
  SELECT
    c.*,
    m.uniq_med_count,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort c
  JOIN med_counts m
    ON c.subject_id = m.subject_id
   AND c.hadm_id = m.hadm_id
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY uniq_med_count) AS tertile
  FROM cohort_with_meds
),
readmit_flags AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.tertile,
    t.los_days,
    t.hospital_expire_flag,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = t.subject_id
        AND a2.hadm_id != t.hadm_id
        AND a2.admittime > t.dischtime
        AND a2.admittime <= DATETIME_ADD(t.dischtime, INTERVAL 30 DAY)
    ) AS readmit_30d
  FROM tertiles t
)
SELECT
  tertile,
  AVG(los_days) AS avg_los_days,
  100 * AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hosp_mortality_pct,
  100 * AVG(CAST(readmit_30d AS INT64)) AS readmit_30d_pct
FROM readmit_flags
GROUP BY tertile
ORDER BY tertile;