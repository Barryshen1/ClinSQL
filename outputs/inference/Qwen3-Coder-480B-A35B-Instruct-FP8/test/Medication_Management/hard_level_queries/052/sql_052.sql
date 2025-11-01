WITH hhs_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code = 'E13.0' AND dd.icd_version = 10
),

patients_filtered AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 68 AND 78
),

target_population AS (
  SELECT
    h.*,
    p.anchor_age,
    p.gender
  FROM
    hhs_admissions h
  JOIN
    patients_filtered p
    ON h.subject_id = p.subject_id
),

all_population AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),

meds_72hr_target AS (
  SELECT
    tp.hadm_id,
    COUNT(DISTINCT em.medication) AS med_count
  FROM
    target_population tp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` em
    ON tp.hadm_id = em.hadm_id
  WHERE
    em.charttime BETWEEN tp.admittime AND DATETIME_ADD(tp.admittime, INTERVAL 72 HOUR)
  GROUP BY
    tp.hadm_id
),

meds_72hr_all AS (
  SELECT
    ap.hadm_id,
    COUNT(DISTINCT em.medication) AS med_count
  FROM
    all_population ap
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` em
    ON ap.hadm_id = em.hadm_id
  WHERE
    em.charttime BETWEEN ap.admittime AND DATETIME_ADD(ap.admittime, INTERVAL 72 HOUR)
  GROUP BY
    ap.hadm_id
),

hyperkalemia_drugs AS (
  SELECT 'spironolactone' AS drug UNION ALL
  SELECT 'eplerenone' UNION ALL
  SELECT 'lisinopril' UNION ALL
  SELECT 'losartan' UNION ALL
  SELECT 'enalapril' UNION ALL
  SELECT 'furosemide' UNION ALL
  SELECT 'hydrochlorothiazide' UNION ALL
  SELECT 'metoprolol' UNION ALL
  SELECT 'carvedilol' UNION ALL
  SELECT 'ibuprofen' UNION ALL
  SELECT 'naproxen' UNION ALL
  SELECT 'ketorolac' UNION ALL
  SELECT 'diclofenac' UNION ALL
  SELECT 'celecoxib' UNION ALL
  SELECT 'amiodarone' UNION ALL
  SELECT 'heparin' UNION ALL
  SELECT 'cyclosporine' UNION ALL
  SELECT 'tacrolimus'
),

target_hyperkalemia AS (
  SELECT DISTINCT
    tp.hadm_id
  FROM
    target_population tp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` em
    ON tp.hadm_id = em.hadm_id
  JOIN
    hyperkalemia_drugs hk
    ON LOWER(em.medication) LIKE CONCAT('%', hk.drug, '%')
),

all_hyperkalemia AS (
  SELECT DISTINCT
    ap.hadm_id
  FROM
    all_population ap
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` em
    ON ap.hadm_id = em.hadm_id
  JOIN
    hyperkalemia_drugs hk
    ON LOWER(em.medication) LIKE CONCAT('%', hk.drug, '%')
),

target_stats AS (
  SELECT
    'target' AS group_name,
    t.hadm_id,
    COALESCE(m.med_count, 0) AS med_count,
    t.los_days,
    t.hospital_expire_flag,
    CASE WHEN th.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_hyperkalemia_risk
  FROM
    target_population t
  LEFT JOIN
    meds_72hr_target m
    ON t.hadm_id = m.hadm_id
  LEFT JOIN
    target_hyperkalemia th
    ON t.hadm_id = th.hadm_id
),

all_stats AS (
  SELECT
    'all' AS group_name,
    a.hadm_id,
    COALESCE(m.med_count, 0) AS med_count,
    a.los_days,
    a.hospital_expire_flag,
    CASE WHEN ah.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_hyperkalemia_risk
  FROM
    all_population a
  LEFT JOIN
    meds_72hr_all m
    ON a.hadm_id = m.hadm_id
  LEFT JOIN
    all_hyperkalemia ah
    ON a.hadm_id = ah.hadm_id
),

combined_stats AS (
  SELECT * FROM target_stats
  UNION ALL
  SELECT * FROM all_stats
),

percentile_ranks AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY med_count) AS med_complexity_percentile
  FROM
    combined_stats
),

summary_stats AS (
  SELECT
    group_name,
    APPROX_QUANTILES(med_count, 100)[OFFSET(25)] AS q1_med_count,
    APPROX_QUANTILES(med_count, 100)[OFFSET(50)] AS median_med_count,
    APPROX_QUANTILES(med_count, 100)[OFFSET(75)] AS q3_med_count,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS top_quartile_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(has_hyperkalemia_risk) AS pct_with_hyperkalemia_risk,
    APPROX_QUANTILES(
      CASE WHEN has_hyperkalemia_risk = 1 THEN med_complexity_percentile END,
      100
    )[OFFSET(50)] AS median_percentile_hyperkalemia
  FROM
    percentile_ranks
  GROUP BY
    group_name
)

SELECT
  group_name,
  q1_med_count,
  median_med_count,
  q3_med_count,
  top_quartile_los,
  mortality_rate,
  pct_with_hyperkalemia_risk,
  median_percentile_hyperkalemia
FROM
  summary_stats
ORDER BY
  group_name;