WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS adm_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id AND a.subject_id = diag.subject_id
  WHERE p.gender = 'F'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
    )
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_admission BETWEEN 38 AND 48
),
icu_days AS (
  SELECT
    hadm_id,
    SUM(los) AS total_icu_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
icu_groups AS (
  SELECT
    fc.*,
    CASE
      WHEN icd.total_icu_days IS NULL THEN 'No ICU'
      WHEN icd.total_icu_days BETWEEN 1 AND 4 THEN 'ICU 1-4 days'
      WHEN icd.total_icu_days BETWEEN 5 AND 7 THEN 'ICU 5-7 days'
      ELSE 'Exclude'
    END AS icu_group
  FROM filtered_cohort fc
  LEFT JOIN icu_days icd
    ON fc.hadm_id = icd.hadm_id
),
diag_counts AS (
  SELECT
    hd.hadm_id,
    COUNT(*) AS diag_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hd
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON hd.hcpcs_cd = d.code
  WHERE
    d.short_description LIKE '%ECG%'
    OR d.long_description LIKE '%ECG%'
    OR d.long_description LIKE '%echocardiogram%'
    OR (d.code BETWEEN '93000' AND '93010')
    OR (d.code BETWEEN '93040' AND '93042')
  GROUP BY hd.hadm_id
)
SELECT
  ig.icu_group,
  AVG(COALESCE(dc.diag_count, 0)) AS mean_diag_count,
  MIN(COALESCE(dc.diag_count, 0)) AS min_diag_count,
  MAX(COALESCE(dc.diag_count, 0)) AS max_diag_count
FROM icu_groups ig
LEFT JOIN diag_counts dc
  ON ig.hadm_id = dc.hadm_id
WHERE ig.icu_group != 'Exclude'
GROUP BY ig.icu_group;