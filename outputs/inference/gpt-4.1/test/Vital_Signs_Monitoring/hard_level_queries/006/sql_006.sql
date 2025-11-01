WITH vital_itemids AS (
  SELECT
    MAX(CASE WHEN LOWER(label) LIKE '%heart rate%' THEN itemid END) AS hr_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%mean arterial pressure%' THEN itemid END) AS map_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%respiratory rate%' THEN itemid END) AS rr_itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
),

-- Step 2: Identify UGIB ICD codes
ugib_icds AS (
  SELECT DISTINCT icd_code, icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%upper gastrointestinal bleed%'
     OR LOWER(long_title) LIKE '%gi bleed%'
     OR LOWER(long_title) LIKE '%hematemesis%'
     OR LOWER(long_title) LIKE '%melena%'
     OR LOWER(long_title) LIKE '%gastric hemorrhage%'
     OR LOWER(long_title) LIKE '%duodenal hemorrhage%'
     OR LOWER(long_title) LIKE '%bleed%'
     OR LOWER(long_title) LIKE '%hemorrhage%'
),

-- Step 3: Cohort selection (UGIB and controls)
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag,
    CASE WHEN ugib.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_ugib
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    JOIN ugib_icds u
      ON diag.icd_code = u.icd_code AND diag.icd_version = u.icd_version
  ) ugib
    ON icu.subject_id = ugib.subject_id AND icu.hadm_id = ugib.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 60 AND 70
),

-- Step 4: Extract vital signs in first 48h of ICU stay
vitals_48h AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    c.intime,
    c.outtime,
    c.has_ugib,
    c.los,
    c.hospital_expire_flag,
    c.anchor_age, -- Added anchor_age
    TIMESTAMP_TRUNC(ce.charttime, HOUR) AS hour,
    MAX(CASE WHEN ce.itemid = vi.hr_itemid THEN ce.valuenum END) AS hr,
    MAX(CASE WHEN ce.itemid = vi.map_itemid THEN ce.valuenum END) AS map,
    MAX(CASE WHEN ce.itemid = vi.rr_itemid THEN ce.valuenum END) AS rr
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  CROSS JOIN vital_itemids vi
  WHERE ce.itemid IN (vi.hr_itemid, vi.map_itemid, vi.rr_itemid)
  GROUP BY c.stay_id, c.subject_id, c.hadm_id, c.intime, c.outtime, c.has_ugib, c.los, c.hospital_expire_flag, c.anchor_age, hour
),

-- Step 5: Compute hourly instability flags
hourly_instability AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    has_ugib,
    los,
    hospital_expire_flag,
    anchor_age, -- Added anchor_age
    hour,
    hr, map, rr,
    CASE WHEN hr > 100 THEN 1 ELSE 0 END AS tachycardia,
    CASE WHEN map < 65 THEN 1 ELSE 0 END AS low_map,
    CASE WHEN rr > 20 THEN 1 ELSE 0 END AS tachypnea,
    CASE WHEN (hr > 100 OR map < 65 OR rr > 20) THEN 1 ELSE 0 END AS unstable
  FROM vitals_48h
),

-- Step 6: Aggregate VII per ICU stay
vii_per_stay AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    has_ugib,
    los,
    hospital_expire_flag,
    anchor_age, -- Added anchor_age
    COUNTIF(unstable = 1) AS vii_48h,
    COUNTIF(tachycardia = 1) AS tachycardia_hours,
    COUNTIF(low_map = 1) AS low_map_hours,
    COUNTIF(tachypnea = 1) AS tachypnea_hours,
    COUNT(*) AS total_hours
  FROM hourly_instability
  GROUP BY stay_id, subject_id, hadm_id, has_ugib, los, hospital_expire_flag, anchor_age
),

-- Step 7: Compute 95th percentile of VII for UGIB cohort
ugib_vii_percentile AS (
  SELECT
    APPROX_QUANTILES(vii_48h, 100)[95] AS vii_95th
  FROM vii_per_stay
  WHERE has_ugib = 1
),

-- Step 8: Mark top decile (top 10%) of VII in UGIB cohort
ugib_top_decile AS (
  SELECT
    v.*,
    p.vii_95th
  FROM vii_per_stay v
  JOIN ugib_vii_percentile p
    ON v.vii_48h >= p.vii_95th
  WHERE v.has_ugib = 1
),

-- Step 9: Summary stats for top decile UGIB vs controls
summary AS (
  SELECT
    'UGIB_top_decile' AS group_label,
    COUNT(*) AS n_stays,
    AVG(CAST(tachycardia_hours AS FLOAT64) / NULLIF(total_hours,0)) AS pct_tachycardia,
    AVG(CAST(low_map_hours AS FLOAT64) / NULLIF(total_hours,0)) AS pct_low_map,
    AVG(CAST(tachypnea_hours AS FLOAT64) / NULLIF(total_hours,0)) AS pct_tachypnea,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM ugib_top_decile

  UNION ALL

  SELECT
    'Controls' AS group_label,
    COUNT(*) AS n_stays,
    AVG(CAST(tachycardia_hours AS FLOAT64) / NULLIF(total_hours,0)) AS pct_tachycardia,
    AVG(CAST(low_map_hours AS FLOAT64) / NULLIF(total_hours,0)) AS pct_low_map,
    AVG(CAST(tachypnea_hours AS FLOAT64) / NULLIF(total_hours,0)) AS pct_tachypnea,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM vii_per_stay
  WHERE has_ugib = 0
    AND anchor_age BETWEEN 60 AND 70
)

-- Final output: 95th percentile VII for UGIB, and summary stats for top decile vs controls
SELECT
  (SELECT vii_95th FROM ugib_vii_percentile) AS ugib_vii_95th_percentile,
  *
FROM summary
ORDER BY group_label;