WITH cohort AS (
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
      USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

-- Gather medications given/ordered in first 24 hours from prescriptions
meds_from_prescriptions AS (
  SELECT
    c.hadm_id,
    LOWER(TRIM(p.drug)) AS med,
    p.starttime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON p.hadm_id = c.hadm_id
  WHERE
    p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND p.drug IS NOT NULL
),

-- Gather medications from pharmacy table (some meds are recorded there)
meds_from_pharmacy AS (
  SELECT
    c.hadm_id,
    LOWER(TRIM(ph.medication)) AS med,
    ph.starttime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
      ON ph.hadm_id = c.hadm_id
  WHERE
    ph.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND ph.medication IS NOT NULL
),

-- Union distinct medication names per hadm_id in first 24h
meds_union AS (
  SELECT DISTINCT hadm_id, med FROM meds_from_prescriptions
  UNION DISTINCT
  SELECT DISTINCT hadm_id, med FROM meds_from_pharmacy
),

-- Label meds as QT-prolonging or bleeding-risk using curated name lists (case-insensitive via lowercased med)
meds_labeled AS (
  SELECT
    hadm_id,
    med,
    -- QT-prolonging list (illustrative, expand as needed)
    REGEXP_CONTAINS(med, r'\b(haloperidol|ziprasidone|methadone|citalopram|escitalopram|amiodarone|sotalol|levofloxacin|moxifloxacin|ondansetron|erythromycin|clarithromycin|procainamide|quinidine|dofetilide|azithromycin)\b') AS is_qt,
    -- Bleeding-risk list (illustrative)
    REGEXP_CONTAINS(med, r'\b(aspirin|clopidogrel|warfarin|heparin|enoxaparin|apixaban|rivaroxaban|dabigatran|ticagrelor|prasugrel)\b') AS is_bleed
  FROM
    meds_union
),

-- Aggregate per admission: medication complexity and counts of QT / bleed drugs
med_agg AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(DISTINCT m.med) AS med_count,
    COUNT(DISTINCT CASE WHEN m.is_qt THEN m.med END) AS qt_med_count,
    COUNT(DISTINCT CASE WHEN m.is_bleed THEN m.med END) AS bleed_med_count
  FROM
    cohort c
    LEFT JOIN meds_labeled m
      ON c.hadm_id = m.hadm_id
  GROUP BY
    c.hadm_id, c.subject_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

-- Add percentile rank of med_count across the cohort
med_with_rank AS (
  SELECT
    *,
    100.0 * percent_rank() OVER (ORDER BY med_count) AS med_count_pct_rank
  FROM
    med_agg
),

-- Compute approximate 75th percentile threshold for med_count (top quartile cutoff)
quartile_threshold AS (
  SELECT
    -- APPROX_QUANTILES returns an array of quantiles; 100 bins, index 75 => approx 75th percentile
    (APPROX_QUANTILES(med_count, 100))[OFFSET(75)] AS med_count_75th
  FROM
    med_agg
),

-- Label groups based on presence of QT and/or bleeding meds in first 24h
med_grouped AS (
  SELECT
    m.*,
    CASE
      WHEN m.qt_med_count > 0 AND m.bleed_med_count = 0 THEN 'QT'
      WHEN m.bleed_med_count > 0 AND m.qt_med_count = 0 THEN 'Bleed'
      WHEN m.qt_med_count > 0 AND m.bleed_med_count > 0 THEN 'Both'
      ELSE 'General'
    END AS risk_group
  FROM
    med_with_rank m
),

-- Summary statistics per group
group_summary AS (
  SELECT
    mg.risk_group,
    COUNT(*) AS n_patients,
    AVG(mg.med_count) AS mean_med_count,
    -- approximate median (50th percentile)
    (APPROX_QUANTILES(mg.med_count, 2))[OFFSET(1)] AS median_med_count,
    AVG(mg.med_count_pct_rank) AS avg_med_count_pct_rank, -- average percentile rank (0-100)
    -- LOS in hospital days (allow fractional days)
    AVG(SAFE_DIVIDE(TIMESTAMP_DIFF(mg.dischtime, mg.admittime, MINUTE), 60.0*24.0)) AS mean_los_days,
    -- mortality rate (hospital_expire_flag is 1 when patient died in hospitalization)
    AVG(CAST(mg.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    med_grouped mg
  GROUP BY
    mg.risk_group
),

-- Summary statistics for top quartile (med_count >= 75th percentile) by group
top_quartile_summary AS (
  SELECT
    mg.risk_group,
    COUNT(*) AS n_topq_patients,
    AVG(SAFE_DIVIDE(TIMESTAMP_DIFF(mg.dischtime, mg.admittime, MINUTE), 60.0*24.0)) AS topq_mean_los_days,
    AVG(CAST(mg.hospital_expire_flag AS FLOAT64)) AS topq_mortality_rate
  FROM
    med_grouped mg
    CROSS JOIN quartile_threshold qt
  WHERE
    mg.med_count >= qt.med_count_75th
  GROUP BY
    mg.risk_group
)

-- Final combined output: group-level metrics and top-quartile metrics side by side
SELECT
  gs.risk_group AS group_label,
  gs.n_patients,
  gs.mean_med_count,
  gs.median_med_count,
  ROUND(gs.avg_med_count_pct_rank,2) AS avg_med_count_pct_rank_0_100,
  ROUND(gs.mean_los_days,3) AS mean_los_days,
  ROUND(gs.mortality_rate,4) AS mortality_rate,
  COALESCE(tq.n_topq_patients, 0) AS n_top_quartile_patients,
  ROUND(COALESCE(tq.topq_mean_los_days, 0),3) AS topq_mean_los_days,
  ROUND(COALESCE(tq.topq_mortality_rate, 0),4) AS topq_mortality_rate
FROM
  group_summary gs
  LEFT JOIN top_quartile_summary tq
    ON gs.risk_group = tq.risk_group
ORDER BY
  -- present in a logical order: QT, Bleed, Both, General
  CASE gs.risk_group
    WHEN 'QT' THEN 1
    WHEN 'Bleed' THEN 2
    WHEN 'Both' THEN 3
    WHEN 'General' THEN 4
    ELSE 5
  END;