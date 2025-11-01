WITH base_icu_patients AS (
    -- Base CTE to get all ICU stays with patient demographics and admission outcomes
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        adm.hadm_id,
        -- hospital_expire_flag indicates if the patient died during this hospital admission
        adm.hospital_expire_flag,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        icu.los
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id AND p.subject_id = icu.subject_id
),
arf_hadm_ids AS (
    -- CTE to identify admissions with Acute Respiratory Failure (ARF) diagnoses
    -- ICD-10 codes for Acute Respiratory Failure: J96.0% (Acute), J96.2% (Acute and chronic)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
      AND (icd_code LIKE 'J96.0%' OR icd_code LIKE 'J96.2%')
),
icu_vitals_72hr AS (
    -- CTE to extract relevant vital sign data (MAP and HR) for all ICU stays
    -- within the first 72 hours of the ICU admission.
    -- Includes demographic, admission, stay info, and ARF status.
    SELECT
        bip.subject_id,
        bip.hadm_id,
        bip.stay_id,
        bip.intime,
        bip.outtime,
        bip.los,
        bip.hospital_expire_flag,
        bip.gender,
        bip.anchor_age,
        (CASE WHEN arf.hadm_id IS NOT NULL THEN TRUE ELSE FALSE END) AS has_arf,
        ce.charttime,
        ce.itemid,
        ce.valuenum
    FROM base_icu_patients bip
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON bip.stay_id = ce.stay_id
    LEFT JOIN arf_hadm_ids arf ON bip.hadm_id = arf.hadm_id
    WHERE ce.itemid IN (
            220052, -- Arterial Blood Pressure mean (MAP)
            220181, -- Non Invasive Blood Pressure mean (NIBP MAP)
            220045  -- Heart Rate
        )
      AND ce.valuenum IS NOT NULL -- Ensure numeric value exists
      -- Filter to the first 72 hours of the ICU stay
      AND ce.charttime BETWEEN bip.intime AND DATETIME_ADD(bip.intime, INTERVAL 72 HOUR)
),
icu_stay_metrics AS (
    -- CTE to calculate crisis counts (burdens) for each ICU stay
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        outtime,
        los,
        hospital_expire_flag,
        gender,
        anchor_age,
        has_arf,
        -- Count of MAP readings below 65 mmHg
        SUM(CASE WHEN itemid IN (220052, 220181) AND valuenum < 65 THEN 1 ELSE 0 END) AS map_crisis_count,
        -- Count of HR readings above 100 bpm
        SUM(CASE WHEN itemid = 220045 AND valuenum > 100 THEN 1 ELSE 0 END) AS hr_crisis_count,
        -- Total count of distinct MAP readings used for burden calculation
        COUNT(DISTINCT CASE WHEN itemid IN (220052, 220181) THEN charttime END) AS map_total_readings,
        -- Total count of distinct HR readings used for burden calculation
        COUNT(DISTINCT CASE WHEN itemid = 220045 THEN charttime END) AS hr_total_readings
    FROM icu_vitals_72hr
    GROUP BY
        subject_id, hadm_id, stay_id, intime, outtime, los, hospital_expire_flag,
        gender, anchor_age, has_arf
),
icu_stay_final_scores AS (
    -- CTE to calculate the composite instability score and proportional burdens for each ICU stay
    SELECT
        *,
        (map_crisis_count + hr_crisis_count) AS composite_instability_score,
        -- Proportional burden for MAP crisis
        SAFE_DIVIDE(map_crisis_count, map_total_readings) AS avg_map_burden_proportion,
        -- Proportional burden for HR crisis
        SAFE_DIVIDE(hr_crisis_count, hr_total_readings) AS avg_hr_burden_proportion
    FROM icu_stay_metrics
)
-- Main query to compare the subgroup to the general ICU population
SELECT
    'Subgroup: 82-92 Male ARF' AS cohort,
    COUNT(DISTINCT subject_id) AS num_patients,
    COUNT(DISTINCT stay_id) AS num_stays,
    -- Composite instability score statistics
    AVG(composite_instability_score) AS avg_composite_instability_score,
    APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(25)] AS composite_instability_p25,
    APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(50)] AS composite_instability_median,
    APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(75)] AS composite_instability_p75,
    (APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(75)] - APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(25)]) AS composite_instability_iqr,
    -- Individual average burdens (as counts)
    AVG(map_crisis_count) AS avg_map_crisis_raw_count,
    AVG(hr_crisis_count) AS avg_hr_crisis_raw_count,
    -- Individual average burdens (as proportions)
    AVG(avg_map_burden_proportion) AS avg_map_crisis_proportion,
    AVG(avg_hr_burden_proportion) AS avg_hr_crisis_proportion,
    -- Average ICU Length of Stay
    AVG(los) AS avg_icu_los_days,
    -- Mortality rate (hospital mortality associated with the ICU stay)
    SUM(hospital_expire_flag) AS num_icu_stay_deaths,
    COUNT(DISTINCT stay_id) AS num_icu_stays_total,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT stay_id)) AS mortality_rate
FROM icu_stay_final_scores
WHERE gender = 'M'
  AND anchor_age BETWEEN 82 AND 92
  AND has_arf IS TRUE

UNION ALL

SELECT
    'General ICU' AS cohort,
    COUNT(DISTINCT subject_id) AS num_patients,
    COUNT(DISTINCT stay_id) AS num_stays,
    -- Composite instability score statistics
    AVG(composite_instability_score) AS avg_composite_instability_score,
    APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(25)] AS composite_instability_p25,
    APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(50)] AS composite_instability_median,
    APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(75)] AS composite_instability_p75,
    (APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(75)] - APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(25)]) AS composite_instability_iqr,
    -- Individual average burdens (as counts)
    AVG(map_crisis_count) AS avg_map_crisis_raw_count,
    AVG(hr_crisis_count) AS avg_hr_crisis_raw_count,
    -- Individual average burdens (as proportions)
    AVG(avg_map_burden_proportion) AS avg_map_crisis_proportion,
    AVG(avg_hr_burden_proportion) AS avg_hr_crisis_proportion,
    -- Average ICU Length of Stay
    AVG(los) AS avg_icu_los_days,
    -- Mortality rate (hospital mortality associated with the ICU stay)
    SUM(hospital_expire_flag) AS num_icu_stay_deaths,
    COUNT(DISTINCT stay_id) AS num_icu_stays_total,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT stay_id)) AS mortality_rate
FROM icu_stay_final_scores;