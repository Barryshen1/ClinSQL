WITH
  -- 1) Base inpatients: male, age 81-91 in hosp module
  base_inpatients AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.dod
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 81 AND 91
  ),

  -- 2) Hadm_ids with pulmonary embolism
  pe_hadm AS (
    SELECT DISTINCT b.hadm_id
    FROM base_inpatients AS b
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON di.hadm_id = b.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%pulmonary embolism%'
  ),

  -- 3) Charlson comorbidity components by hadm_id
  charlson_components AS (
    SELECT
      di.hadm_id,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%myocardial infarction%' THEN 1 ELSE 0 END) AS MI,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%congestive heart failure%' OR LOWER(dd.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS CHF,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%peripheral vascular%' THEN 1 ELSE 0 END) AS PVD,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%cerebrovascular%' OR LOWER(dd.long_title) LIKE '%stroke%' THEN 1 ELSE 0 END) AS CVD,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%dementia%' THEN 1 ELSE 0 END) AS Dementia,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic pulmonary%' OR LOWER(dd.long_title) LIKE '%pulmonary disease%' THEN 1 ELSE 0 END) AS CPD,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes with complications%' THEN 1 ELSE 0 END) AS DiabetesComp,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS Diabetes,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%renal%' THEN 1 ELSE 0 END) AS Renal,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%liver%' THEN 1 ELSE 0 END) AS Liver,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%cancer%' OR LOWER(dd.long_title) LIKE '%tumor%' THEN 1 ELSE 0 END) AS Malignancy,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%metastatic%' THEN 1 ELSE 0 END) AS Metastatic,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%AIDS%' OR LOWER(dd.long_title) LIKE '%acquired immune deficiency%' THEN 1 ELSE 0 END) AS AIDS
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    GROUP BY di.hadm_id
  ),

  -- 4) Charlson total score (CCI) with canonical weights
  charlson_score AS (
    SELECT
      c.hadm_id,
      (COALESCE(c.MI,0)  + COALESCE(c.CHF,0) + COALESCE(c.PVD,0) +
       COALESCE(c.CVD,0) + COALESCE(c.Dementia,0) + COALESCE(c.CPD,0) +
       CASE WHEN COALESCE(c.DiabetesComp,0) = 1 THEN 2
            WHEN COALESCE(c.Diabetes,0) = 1 THEN 1
            ELSE 0 END +
       CASE WHEN COALESCE(c.Renal,0) = 1 THEN 2 ELSE 0 END +
       COALESCE(c.Liver,0) +
       CASE WHEN COALESCE(c.Metastatic,0) = 1 THEN 6
            WHEN COALESCE(c.Malignancy,0) = 1 THEN 2
            ELSE 0 END +
       COALESCE(c.AIDS,0)
      ) AS cci
    FROM charlson_components AS c
  ),

  -- 5) AKI/ARDS flags per hadm (for later rates)
  diagnosis_flags AS (
    SELECT
      di.hadm_id,
      MAX(CASE
            WHEN LOWER(dd.long_title) LIKE '%acute kidney injury%' OR
                 LOWER(dd.long_title) LIKE '%acute renal failure%' OR
                 LOWER(dd.long_title) LIKE '%renal failure%'
            THEN 1 ELSE 0 END) AS AKI_present,
      MAX(CASE
            WHEN LOWER(dd.long_title) LIKE '%acute respiratory distress syndrome%' OR
                 LOWER(dd.long_title) LIKE '%ARDS%'
            THEN 1 ELSE 0 END) AS ARDS_present
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    GROUP BY di.hadm_id
  ),

  -- 6) LOS and 90-day mortality indicators
  death_90d AS (
    SELECT
      b.hadm_id,
      CASE
        WHEN p.dod IS NOT NULL AND DATE(p.dod) <= DATE(b.admittime) + INTERVAL 90 DAY
        THEN 1 ELSE 0 END AS mortality_90d
    FROM base_inpatients AS b
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON b.subject_id = p.subject_id
  ),

  los_table AS (
    SELECT
      a.hadm_id,
      DATE(a.dischtime) - DATE(a.admittime) AS LOS_days
    FROM base_inpatients AS a
  ),

  -- 7) 75th percentile of CCI across all base inpatients (male 81-91)
  -- Compute percentile on the CCI values of base inpatients
  all_inpatients_with_cci AS (
    SELECT b.hadm_id, cci_score.cci
    FROM base_inpatients AS b
    JOIN charlson_score AS cci_score
      ON b.hadm_id = cci_score.hadm_id
  ),

  percentile_p75 AS (
    SELECT quant[OFFSET(75)] AS p75
    FROM (
      SELECT APPROX_QUANTILES(cci, 100) AS quant
      FROM all_inpatients_with_cci
    )
  ),

  -- 8) High-comorbidity cohort: PE patients with CCI > 75th percentile
  high_comorbidity_pe AS (
    SELECT
      b.hadm_id,
      b.subject_id,
      b.admittime,
      b.dischtime,
      b.dod,
      cci_score.cci,
      dflag.AKI_present,
      dflag.ARDS_present,
      l.LOS_days
    FROM base_inpatients AS b
    JOIN pe_hadm AS pe
      ON b.hadm_id = pe.hadm_id
    JOIN charlson_score AS cci_score
      ON b.hadm_id = cci_score.hadm_id
    JOIN diagnosis_flags AS dflag
      ON b.hadm_id = dflag.hadm_id
    JOIN los_table AS l
      ON b.hadm_id = l.hadm_id
    CROSS JOIN percentile_p75 AS p75
    WHERE cci_score.cci > p75.p75
  ),

  -- 9) Survivors (within 90 days) and profiles
  survivors AS (
    SELECT *
    FROM high_comorbidity_pe
    WHERE NOT (died_90d = 1)
  ),

  profile_percentiles AS (
    -- Per-hadm percentile of the profile's CCI within the base population
    SELECT h.hadm_id,
           PERCENT_RANK() OVER (ORDER BY h.cci) AS matched_profile_risk_percentile
    FROM high_comorbidity_pe AS h
  )

SELECT
  AVG(h.cci) AS mean_risk_score,                                         -- mean CCI in high-comorbidity PE cohort
  100.0 * SUM(COALESCE(d.mortality_90d, 0)) / COUNT(*) AS mortality_90d,  -- 90-day mortality
  AVG(CASE WHEN dflag.AKI_present = 1 THEN 1.0 ELSE 0.0 END) AS aki_rate_all,       -- AKI rate (all)
  AVG(CASE WHEN dflag.ARDS_present = 1 THEN 1.0 ELSE 0.0 END) AS ards_rate_all,     -- ARDS rate (all)
  SUM(CASE WHEN COALESCE(d.mortality_90d,0) = 0 AND dflag.AKI_present = 1 THEN 1 ELSE 0 END)
    / NULLIF(SUM(CASE WHEN COALESCE(d.mortality_90d,0) = 0 THEN 1 ELSE 0 END), 0) AS aki_rate_survivors, -- AKI among survivors
  SUM(CASE WHEN COALESCE(d.mortality_90d,0) = 0 AND dflag.ARDS_present = 1 THEN 1 ELSE 0 END)
    / NULLIF(SUM(CASE WHEN COALESCE(d.mortality_90d,0) = 0 THEN 1 ELSE 0 END), 0) AS ards_rate_survivors, -- ARDS among survivors
  AVG(CASE WHEN COALESCE(d.mortality_90d,0) = 0 THEN lt.LOS_days END) AS los_mean_survivors,        -- LOS among survivors
  AVG(lt.LOS_days) AS los_mean_all,                                                     -- LOS among all
  AVG(pp.matched_profile_risk_percentile) AS matched_profile_risk_percentile_mean      -- mean matched-profile percentile
FROM high_comorbidity_pe AS h
LEFT JOIN death_90d AS d
  ON h.hadm_id = d.hadm_id
LEFT JOIN diagnosis_flags AS dflag
  ON h.hadm_id = dflag.hadm_id
LEFT JOIN los_table AS lt
  ON h.hadm_id = lt.hadm_id
LEFT JOIN profile_percentiles AS pp
  ON h.hadm_id = pp.hadm_id
;