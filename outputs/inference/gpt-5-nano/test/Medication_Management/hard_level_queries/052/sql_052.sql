WITH
-- 1) Identify hadm_ids with Hyperosmolar Hyperglycemic State (HHS) by long_title
hhs_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%hyperosmolar%'
),

-- 2) Core cohort classification: female, age 68-78 (HHS) vs all inpatients
cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    CASE
      -- Only admissions in HHS set occur in the HHS_68_78_females group
      WHEN h.hadm_id IS NOT NULL
           AND p.gender = 'F'
           AND p.anchor_age BETWEEN 68 AND 78 THEN 'HHS_68_78_females'
      ELSE 'All_inpatients'
    END AS cohort_label
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  LEFT JOIN hhs_hadm AS h
    ON a.hadm_id = h.hadm_id
),

-- 3) 72-hour medication exposure: count distinct drugs started in first 72h
meds72 AS (
  SELECT
    c.hadm_id,
    c.cohort_label,
    COUNT(DISTINCT p.drug) AS meds72
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.hadm_id = c.hadm_id
   AND p.starttime >= c.admittime
   AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id, c.cohort_label
),

-- 4) Binning for 72h meds (treat NULL as 0 for binning)
med_bins AS (
  SELECT
    m.hadm_id,
    m.cohort_label,
    CASE
      WHEN COALESCE(m.meds72, 0) BETWEEN 0 AND 2 THEN '0-2'
      WHEN COALESCE(m.meds72, 0) BETWEEN 3 AND 4 THEN '3-4'
      WHEN COALESCE(m.meds72, 0) BETWEEN 5 AND 6 THEN '5-6'
      WHEN COALESCE(m.meds72, 0) BETWEEN 7 AND 9 THEN '7-9'
      WHEN COALESCE(m.meds72, 0) >= 10 THEN '10+'
    END AS meds_bin
  FROM meds72 m
),

-- 5) Hyperkalemia-risk interactions proxy
risks_raas AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) IN (
    'spironolactone','eplerenone','triamterene','amiloride',
    'losartan','valsartan','lisinopril','enalapril','ramipril','captopril',
    'olmesartan','telmisartan','irbesartan','candesartan'
  )
),
risks_kpot AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%potassium%'
),
risk_hadm AS (
  SELECT DISTINCT r1.hadm_id
  FROM risks_raas r1
  INNER JOIN risks_kpot r2 ON r1.hadm_id = r2.hadm_id
),
risk_flags AS (
  SELECT c.hadm_id,
         c.cohort_label,
         CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS hyperkalemia_risk
  FROM cohort AS c
  LEFT JOIN risk_hadm r ON c.hadm_id = r.hadm_id
),

-- 6) LOS and mortality computation
los_table AS (
  SELECT
    rf.hadm_id,
    rf.cohort_label,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)/3600.0 AS los_hours,
    CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mort
  FROM risk_flags AS rf
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = rf.hadm_id
),

los_rank AS (
  SELECT l.*,
         PERCENT_RANK() OVER (PARTITION BY l.cohort_label ORDER BY l.los_hours) AS los_pct_rank
  FROM los_table AS l
),

risk_los_rank AS (
  SELECT *
  FROM los_rank
),

-- 7) Top-quartile LOS threshold per cohort (using approximate quantiles)
per_cohort AS (
  SELECT cohort_label, APPROX_QUANTILES(los_hours, 100) AS quant
  FROM los_rank
  GROUP BY cohort_label
),
top_quart AS (
  SELECT cohort_label AS cohort, quant[OFFSET(75)] AS top_los
  FROM per_cohort
),

-- 8) Median los_pct_rank among hyperkalemia-risk patients per cohort (via approx quantiles)
risk_medians AS (
  SELECT cohort_label, APPROX_QUANTILES(los_pct_rank, 100) AS quant
  FROM risk_los_rank
  WHERE hyperkalemia_risk = 1
  GROUP BY cohort_label
)

SELECT
  m.cohort_label AS cohort,

  -- 72h medication distribution (counts per bin)
  SUM(CASE WHEN b.meds_bin = '0-2' THEN 1 ELSE 0 END) AS n_0_2,
  SUM(CASE WHEN b.meds_bin = '3-4' THEN 1 ELSE 0 END) AS n_3_4,
  SUM(CASE WHEN b.meds_bin = '5-6' THEN 1 ELSE 0 END) AS n_5_6,
  SUM(CASE WHEN b.meds_bin = '7-9' THEN 1 ELSE 0 END) AS n_7_9,
  SUM(CASE WHEN b.meds_bin = '10+' THEN 1 ELSE 0 END) AS n_10p,

  -- percent affected by hyperkalemia-risk interactions
  SAFE_DIVIDE(
    SUM(CASE WHEN rf.hyperkalemia_risk = 1 THEN 1 ELSE 0 END),
    COUNT(*)
  ) * 100 AS percent_affected,

  -- median LOS percentile rank among risk patients
  (SELECT quant[OFFSET(50)]
     FROM risk_medians rm
     WHERE rm.cohort_label = m.cohort_label
  ) AS median_los_pct_rank_risk_group,

  -- top-quartile LOS threshold
  t.top_los AS top_quartile_los_hours,

  -- mortality within the top-quartile LOS
  (SELECT AVG(lmort.mort)
     FROM los_rank lmort
     JOIN top_quart tq ON lmort.cohort_label = tq.cohort
     WHERE lmort.cohort_label = m.cohort_label
       AND lmort.los_hours >= tq.top_los
  ) AS mortality_top_quartile

FROM cohort AS m
LEFT JOIN meds72 AS mp ON m.hadm_id = mp.hadm_id
LEFT JOIN med_bins AS b ON mp.hadm_id = b.hadm_id
LEFT JOIN risk_flags AS rf ON m.hadm_id = rf.hadm_id
LEFT JOIN los_table AS l ON m.hadm_id = l.hadm_id
LEFT JOIN top_quart t ON m.cohort_label = t.cohort
GROUP BY m.cohort_label, t.top_los
ORDER BY m.cohort_label;