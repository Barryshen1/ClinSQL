WITH hf_admissions AS (
  -- Identify HF admissions and classify primary vs secondary HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- flag primary HF diagnosis
    MAX(CASE
          WHEN d.seq_num = 1 THEN 1
          ELSE 0
        END) AS primary_hf_flag,
    -- flag any secondary HF diagnosis
    MAX(CASE
          WHEN d.seq_num > 1 THEN 1
          ELSE 0
        END) AS secondary_hf_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%heart failure%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
),
adm_cohort AS (
  -- Filter by demographics and LOS, and tag primary vs secondary
  SELECT
    h.subject_id,
    h.hadm_id,
    h.los_days,
    CASE
      WHEN h.primary_hf_flag = 1 THEN 'Primary'
      WHEN h.primary_hf_flag = 0
           AND h.secondary_hf_flag = 1 THEN 'Secondary'
      ELSE 'Other'
    END AS diag_type,
    CASE
      WHEN h.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN h.los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_bin
  FROM
    hf_admissions h
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON h.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON h.hadm_id    = a.hadm_id
      AND h.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND h.los_days BETWEEN 1 AND 7
    AND CASE
          WHEN h.primary_hf_flag = 1 THEN 'Primary'
          WHEN h.primary_hf_flag = 0
               AND h.secondary_hf_flag = 1 THEN 'Secondary'
        END IS NOT NULL
),
ct_mri_counts AS (
  -- Count CT & MRI per admission
  SELECT
    c.subject_id,
    c.hadm_id,
    c.diag_type,
    c.los_bin,
    COUNTIF(LOWER(hc.short_description) LIKE '%ct%')   AS ct_count,
    COUNTIF(LOWER(hc.short_description) LIKE '%mri%')  AS mri_count
  FROM
    adm_cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
      ON c.hadm_id = hc.hadm_id
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.diag_type,
    c.los_bin
)
-- Final aggregation: mean/min/max CT & MRI per (diag_type, los_bin)
SELECT
  diag_type,
  los_bin,
  ROUND(AVG(ct_count), 2)  AS mean_ct,
  MIN(ct_count)            AS min_ct,
  MAX(ct_count)            AS max_ct,
  ROUND(AVG(mri_count), 2) AS mean_mri,
  MIN(mri_count)           AS min_mri,
  MAX(mri_count)           AS max_mri
FROM
  ct_mri_counts
GROUP BY
  diag_type,
  los_bin
ORDER BY
  diag_type,
  los_bin;