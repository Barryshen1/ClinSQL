WITH num_diagnoses_per_hadm AS (
    SELECT
        hadm_id,
        COUNT(DISTINCT icd_code) AS num_diagnoses_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
base_admissions AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        pa.gender,
        pa.anchor_age,
        COALESCE(nd.num_diagnoses_count, 0) AS comorbidity_score, -- Using number of distinct diagnoses as a proxy for comorbidity
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_hospital,
        CASE
            -- Corrected 90-day mortality logic: death occurred within 90 days after admission
            WHEN ad.deathtime IS NOT NULL 
                AND ad.deathtime BETWEEN ad.admittime AND TIMESTAMP_ADD(ad.admittime, INTERVAL 90 DAY) THEN 1
            ELSE 0
        END AS ninety_day_mortality_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    LEFT JOIN
        num_diagnoses_per_hadm nd
        ON ad.hadm_id = nd.hadm_id
    WHERE
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) >= 0 -- Exclude admissions with illogical LOS
),
diagnoses_flags AS (
    SELECT
        hadm_id,
        -- Pulmonary Embolism (PE) - ICD-9: 415.1, ICD-10: I26
        MAX(CASE WHEN di.icd_version = 9 AND di.icd_code LIKE '415.1%' THEN 1
                 WHEN di.icd_version = 10 AND di.icd_code LIKE 'I26%' THEN 1
                 ELSE 0 END) AS has_pulmonary_embolism,
        -- Acute Kidney Injury (AKI) - ICD-9: 584, ICD-10: N17
        MAX(CASE WHEN di.icd_version = 9 AND di.icd_code LIKE '584%' THEN 1
                 WHEN di.icd_version = 10 AND di.icd_code LIKE 'N17%' THEN 1
                 ELSE 0 END) AS has_aki,
        -- Acute Respiratory Distress Syndrome (ARDS) - ICD-9: 518.5, 518.82, ICD-10: J80
        MAX(CASE WHEN di.icd_version = 9 AND (di.icd_code = '5185' OR di.icd_code = '51882') THEN 1 -- ICD9 codes are 518.5 and 518.82, '5185' and '51882' are likely codes without '.'
                -- Checking against typical ICD-9 codes which may omit the decimal for matching.
                 WHEN di.icd_version = 9 AND (di.icd_code = '518.5' OR di.icd_code = '518.82') THEN 1
                 WHEN di.icd_version = 10 AND di.icd_code = 'J80' THEN 1
                 ELSE 0 END) AS has_ards
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    GROUP BY
        hadm_id
),
all_admissions_data AS (
    SELECT
        ba.*,
        COALESCE(df.has_pulmonary_embolism, 0) AS has_pulmonary_embolism,
        COALESCE(df.has_aki, 0) AS has_aki,
        COALESCE(df.has_ards, 0) AS has_ards
    FROM
        base_admissions ba
    LEFT JOIN
        diagnoses_flags df
        ON ba.hadm_id = df.hadm_id
),
comorbidity_percentile_threshold AS (
    SELECT
        -- Calculate the 75th percentile of comorbidity scores (number of diagnoses) across all admissions
        PERCENTILE_CONT(comorbidity_score, 0.75) AS percentile_75_score -- Corrected syntax for PERCENTILE_CONT
    FROM
        all_admissions_data
),
target_population AS (
    SELECT
        *
    FROM
        all_admissions_data
    WHERE
        gender = 'M'
        AND anchor_age BETWEEN 81 AND 91
        AND has_pulmonary_embolism = 1
        AND comorbidity_score > (SELECT percentile_75_score FROM comorbidity_percentile_threshold)
),
all_inpatients_summary AS (
    SELECT
        AVG(los_hospital) AS all_inpatients_mean_los,
        SUM(has_aki) * 100.0 / COUNT(hadm_id) AS all_inpatients_aki_rate,
        SUM(has_ards) * 100.0 / COUNT(hadm_id) AS all_inpatients_ards_rate
    FROM
        all_admissions_data
),
target_population_summary AS (
    SELECT
        AVG(comorbidity_score) AS target_mean_comorbidity_score,
        SUM(ninety_day_mortality_flag) * 100.0 / COUNT(hadm_id) AS target_90_day_mortality_rate
    FROM
        target_population
),
target_survivors_summary AS (
    SELECT
        AVG(los_hospital) AS target_survivors_mean_los, -- AVG correctly handles NULLs, explicit IF not strictly necessary
        SUM(has_aki) * 100.0 / COUNT(hadm_id) AS target_survivors_aki_rate,
        SUM(has_ards) * 100.0 / COUNT(hadm_id) AS target_survivors_ards_rate
    FROM
        target_population
    WHERE
        ninety_day_mortality_flag = 0
)
SELECT
    'Target Population (Male, 81-91, PE, High Comorbidity):' AS group_description,
    tps.target_mean_comorbidity_score,
    tps.target_90_day_mortality_rate,
    ' ' AS spacer_1,
    'Target Population Survivors:' AS group_description_survivors,
    tss.target_survivors_mean_los AS mean_los_if_survivor,
    tss.target_survivors_aki_rate AS aki_rate_if_survivor,
    tss.target_survivors_ards_rate AS ards_rate_if_survivor,
    ' ' AS spacer_2,
    'All Inpatients Comparison:' AS group_description_all,
    ais.all_inpatients_mean_los,
    ais.all_inpatients_aki_rate,
    ais.all_inpatients_ards_rate,
    ' ' AS spacer_3,
    (
        SELECT
            (SUM(CASE WHEN aad.comorbidity_score <= (SELECT target_mean_comorbidity_score FROM target_population_summary) THEN 1 ELSE 0 END) * 100.0) / COUNT(aad.comorbidity_score)
        FROM
            all_admissions_data aad
    ) AS matched_profile_risk_percentile
FROM
    target_population_summary tps,
    target_survivors_summary tss,
    all_inpatients_summary ais;