WITH postop_complications_icd AS (
  -- ICD-10 codes for postoperative complications (expand as needed)
  SELECT 'T81' AS icd_prefix UNION ALL
  SELECT 'T82' UNION ALL
  SELECT 'T83' UNION ALL
  SELECT 'T84' UNION ALL
  SELECT 'T85' UNION ALL
  SELECT 'T86' UNION ALL
  SELECT 'T87' UNION ALL
  SELECT 'T88'
),
charlson_weights AS (
  -- Example mapping: icd_code, icd_version, charlson_weight
  -- Expand with full mapping per Quan et al. 2005
  SELECT 'I21' AS icd_code, 10 AS icd_version, 1 AS weight UNION ALL -- MI
  SELECT 'I50', 10, 1 UNION ALL -- CHF
  SELECT 'I63', 10, 1 UNION ALL -- Stroke
  SELECT 'C34', 10, 2 UNION ALL -- Cancer
  SELECT 'N18', 10, 2 UNION ALL -- CKD
  SELECT 'B20', 10, 6 -- AIDS
  -- Add more mappings as needed
),
admissions_filtered AS (
  -- 44-year-old male with postoperative complications
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    a.admission_type
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age = 44
    AND p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN postop_complications_icd icd
        ON (d.icd_version = 10 AND LEFT(d.icd_code, 3) = icd.icd_prefix)
      WHERE d.hadm_id = a.hadm_id
    )
),
charlson_per_admission AS (
  -- Sum Charlson weights per admission
  SELECT
    d.hadm_id,
    SUM(w.weight) AS charlson_index
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN charlson_weights w
    ON d.icd_version = w.icd_version AND LEFT(d.icd_code, 3) = LEFT(w.icd_code, 3)
  GROUP BY d.hadm_id
),
first_icustay_per_hadm AS (
  -- Get the earliest ICU stay per hadm_id
  SELECT
    hadm_id,
    MIN(intime) AS first_intime
  FROM physionet-data.mimiciv_3_1_icu.icustays
  GROUP BY hadm_id
),
icu_status AS (
  -- ICU vs non-ICU
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE WHEN f.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM admissions_filtered a
  LEFT JOIN first_icustay_per_hadm f
    ON a.hadm_id = f.hadm_id
),
los_bins AS (
  -- LOS bins
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    icu.icu_status,
    IFNULL(c.charlson_index, 0) AS charlson_index,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 3 THEN '≤3'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 6 THEN '4–6'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 7 AND 10 THEN '7–10'
      ELSE '>10'
    END AS los_bin,
    CASE
      WHEN IFNULL(c.charlson_index, 0) <= 3 THEN '≤3'
      WHEN IFNULL(c.charlson_index, 0) BETWEEN 4 AND 5 THEN '4–5'
      ELSE '>5'
    END AS charlson_bin
  FROM admissions_filtered a
  LEFT JOIN charlson_per_admission c
    ON a.hadm_id = c.hadm_id
  LEFT JOIN icu_status icu
    ON a.hadm_id = icu.hadm_id
),
interventions AS (
  -- For each admission, flag if mechanical ventilation, vasopressors, RRT occurred
  SELECT
    l.hadm_id,
    MAX(CASE WHEN mv.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN vp.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS vasopressor,
    MAX(CASE WHEN rrt.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS rrt
  FROM los_bins l
  LEFT JOIN (
    -- Mechanical ventilation: chartevents/procedureevents itemids (example: 224687, 224685, 224684)
    SELECT DISTINCT hadm_id, stay_id
    FROM physionet-data.mimiciv_3_1_icu.chartevents
    WHERE itemid IN (224687, 224685, 224684)
  ) mv ON l.hadm_id = mv.hadm_id
  LEFT JOIN (
    -- Vasopressors: inputevents itemids (example: 221906, 221289, 221662, 221653, 221749)
    SELECT DISTINCT hadm_id, stay_id
    FROM physionet-data.mimiciv_3_1_icu.inputevents
    WHERE itemid IN (221906, 221289, 221662, 221653, 221749)
  ) vp ON l.hadm_id = vp.hadm_id
  LEFT JOIN (
    -- RRT: procedureevents itemids (example: 227558, 227559, 227560)
    SELECT DISTINCT hadm_id, stay_id
    FROM physionet-data.mimiciv_3_1_icu.procedureevents
    WHERE itemid IN (227558, 227559, 227560)
  ) rrt ON l.hadm_id = rrt.hadm_id
  GROUP BY l.hadm_id
),
final AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.icu_status,
    l.los_bin,
    l.charlson_bin,
    l.hospital_expire_flag,
    l.charlson_index,
    interventions.mech_vent,
    interventions.vasopressor,
    interventions.rrt
  FROM los_bins l
  LEFT JOIN interventions
    ON l.hadm_id = interventions.hadm_id
),
summary AS (
  -- Aggregate by ICU status, LOS bin, Charlson bin
  SELECT
    icu_status,
    los_bin,
    charlson_bin,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_pct,
    SUM(mech_vent) AS n_mech_vent,
    100.0 * SUM(mech_vent) / COUNT(*) AS mech_vent_pct,
    SUM(vasopressor) AS n_vasopressor,
    100.0 * SUM(vasopressor) / COUNT(*) AS vasopressor_pct,
    SUM(rrt) AS n_rrt,
    100.0 * SUM(rrt) / COUNT(*) AS rrt_pct
  FROM final
  GROUP BY icu_status, los_bin, charlson_bin
),
reference AS (
  -- Reference group: ≤3 days LOS
  SELECT
    icu_status,
    charlson_bin,
    mortality_pct AS ref_mortality_pct
  FROM summary
  WHERE los_bin = '≤3'
)
SELECT
  s.icu_status,
  s.los_bin,
  s.charlson_bin,
  s.n_admissions,
  s.mortality_pct,
  s.mech_vent_pct,
  s.vasopressor_pct,
  s.rrt_pct,
  -- Absolute and relative difference vs ≤3 days
  r.ref_mortality_pct,
  s.mortality_pct - r.ref_mortality_pct AS abs_diff_vs_le3,
  SAFE_DIVIDE(s.mortality_pct - r.ref_mortality_pct, r.ref_mortality_pct) AS rel_diff_vs_le3
FROM summary s
LEFT JOIN reference r
  ON s.icu_status = r.icu_status AND s.charlson_bin = r.charlson_bin
ORDER BY s.icu_status, s.charlson_bin, s.los_bin;