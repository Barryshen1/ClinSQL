WITH asthma_icd_codes AS (
    SELECT '49301' AS icd_code, 9 AS icd_version UNION ALL -- Asthma, extrinsic, with status asthmaticus
    SELECT '49311', 9 UNION ALL -- Asthma, intrinsic, with status asthmaticus
    SELECT '49321', 9 UNION ALL -- Asthma, chronic obstructive, with status asthmaticus
    SELECT '49391', 9 UNION ALL -- Asthma, unspecified, with status asthmaticus
    SELECT '49302', 9 UNION ALL -- Extrinsic asthma with acute exacerbation
    SELECT '49312', 9 UNION ALL -- Intrinsic asthma with acute exacerbation
    SELECT '49322', 9 UNION ALL -- Chronic obstructive asthma with acute exacerbation
    SELECT '49392', 9 UNION ALL -- Unspecified asthma with acute exacerbation
    SELECT 'J4521', 10 UNION ALL -- Mild intermittent asthma with (acute) exacerbation
    SELECT 'J4531', 10 UNION ALL -- Moderate persistent asthma with (acute) exacerbation
    SELECT 'J4541', 10 UNION ALL -- Severe persistent asthma with (acute) exacerbation
    SELECT 'J4551', 10 UNION ALL -- Unspecified asthma with (acute) exacerbation
    SELECT 'J45901', 10 UNION ALL -- Unspecified asthma with (acute) exacerbation
    SELECT 'J45991', 10        -- Other asthma with (acute) exacerbation
),
-- Step 2: Identify all admissions for the target cohort:
-- Male patients, aged 52-62, with an asthma exacerbation diagnosis
target_cohort_admissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        (pa.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pa.anchor_year)) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON adm.subject_id = pa.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON adm.hadm_id = di.hadm_id
    JOIN asthma_icd_codes aic
        ON di.icd_code = aic.icd_code AND di.icd_version = aic.icd_version
    WHERE pa.gender = 'M'
    AND (pa.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pa.anchor_year)) BETWEEN 52 AND 62
),
-- Step 3a: Calculate MIN/MAX/COUNT for each lab item within the first 72 hours of admission
lab_instability_per_item AS (
    SELECT
        tca.hadm_id,
        le.itemid,
        MIN(le.valuenum) AS min_val,
        MAX(le.valuenum) AS max_val,
        COUNT(le.valuenum) AS num_measures
    FROM target_cohort_admissions tca
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON tca.hadm_id = le.hadm_id
    WHERE
        le.charttime >= tca.admittime
        AND le.charttime < DATETIME_ADD(tca.admittime, INTERVAL 72 HOUR)
        AND le.valuenum IS NOT NULL
    GROUP BY
        tca.hadm_id, le.itemid
),
-- Step 3b: Aggregate lab instability score per admission
-- Score is the sum of (MAX - MIN) for labs measured >= 2 times in 72 hours
lab_instability_calc AS (
    SELECT
        tca.hadm_id,
        tca.subject_id,
        tca.admittime,
        tca.dischtime,
        tca.hospital_expire_flag,
        COALESCE(SUM(
            CASE
                WHEN lipi.num_measures >= 2 THEN (lipi.max_val - lipi.min_val)
                ELSE 0
            END
        ), 0) AS lab_instability_score
    FROM target_cohort_admissions tca
    LEFT JOIN lab_instability_per_item lipi
        ON tca.hadm_id = lipi.hadm_id
    GROUP BY
        tca.hadm_id, tca.subject_id, tca.admittime, tca.dischtime, tca.hospital_expire_flag
),
-- Step 4: Calculate the 90th percentile of the lab instability score for the target cohort
percentile_threshold AS (
    SELECT
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY lab_instability_score) AS p90_score -- Refined syntax for aggregate percentile
    FROM lab_instability_calc
    WHERE lab_instability_score IS NOT NULL
),
-- Step 5: Identify the top decile of asthma admissions based on instability score
-- NTILE(10) assigns ranks, with 1 being the top 10%
asthma_top_decile_admissions AS (
    SELECT
        lic.*,
        NTILE(10) OVER (ORDER BY lic.lab_instability_score DESC) AS decile_rank
    FROM lab_instability_calc lic
    WHERE lic.lab_instability_score IS NOT NULL
),
-- Step 6: Calculate metrics for the top decile of asthma patients
asthma_top_decile_metrics AS (
    SELECT
        'Asthma Exacerbation Top 10% Instability' AS group_name,
        COUNT(DISTINCT atda.hadm_id) AS num_admissions,
        SUM(atda.hospital_expire_flag) AS total_deaths,
        CAST(AVG(atda.hospital_expire_flag) AS NUMERIC) AS mortality_rate,
        CAST(AVG(DATETIME_DIFF(atda.dischtime, atda.admittime, HOUR) / 24.0) AS NUMERIC) AS mean_los_days,
        COALESCE(CAST(AVG(critical_labs.critical_lab_count) AS NUMERIC), 0) AS avg_critical_lab_events
    FROM asthma_top_decile_admissions atda
    LEFT JOIN (
        SELECT
            le.hadm_id,
            COUNT(*) AS critical_lab_count
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` le -- Removed JOIN d_labitems
        WHERE le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL -- Fixed to use le.ref_range_lower
        AND le.ref_range_upper IS NOT NULL -- Fixed to use le.ref_range_upper
        -- Critical if valuenum is outside the reference range (exclusive at boundaries)
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
        GROUP BY le.hadm_id
    ) AS critical_labs
        ON atda.hadm_id = critical_labs.hadm_id
    WHERE atda.decile_rank = 1
    GROUP BY 1
),
-- Step 7: Identify the control group (age-matched males without *current admission* asthma exacerbation)
control_admissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON adm.subject_id = pa.subject_id
    WHERE pa.gender = 'M'
    AND (pa.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pa.anchor_year)) BETWEEN 52 AND 62
    AND adm.hadm_id NOT IN (SELECT hadm_id FROM target_cohort_admissions)
),
-- Step 8: Calculate metrics for the control group
control_group_metrics AS (
    SELECT
        'Age-Matched Male Controls (Non-Asthma)' AS group_name,
        COUNT(DISTINCT ca.hadm_id) AS num_admissions,
        SUM(ca.hospital_expire_flag) AS total_deaths,
        CAST(AVG(ca.hospital_expire_flag) AS NUMERIC) AS mortality_rate,
        CAST(AVG(DATETIME_DIFF(ca.dischtime, ca.admittime, HOUR) / 24.0) AS NUMERIC) AS mean_los_days,
        COALESCE(CAST(AVG(critical_labs_control.critical_lab_count) AS NUMERIC), 0) AS avg_critical_lab_events
    FROM control_admissions ca
    LEFT JOIN (
        SELECT
            le.hadm_id,
            COUNT(*) AS critical_lab_count
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` le -- Removed JOIN d_labitems
        WHERE le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL -- Fixed to use le.ref_range_lower
        AND le.ref_range_upper IS NOT NULL -- Fixed to use le.ref_range_upper
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper) -- Fixed condition
        GROUP BY le.hadm_id
    ) AS critical_labs_control
        ON ca.hadm_id = critical_labs_control.hadm_id
    GROUP BY 1
)
-- Step 9: Combine and report the results
SELECT
    (SELECT p90_score FROM percentile_threshold) AS `90th_percentile_72hr_lab_instability_score`,
    tdm.group_name,
    tdm.num_admissions,
    tdm.total_deaths,
    tdm.mortality_rate,
    tdm.mean_los_days,
    tdm.avg_critical_lab_events
FROM asthma_top_decile_metrics tdm
UNION ALL
SELECT
    NULL AS `90th_percentile_72hr_lab_instability_score`, -- Not applicable for control group in this context
    cgm.group_name,
    cgm.num_admissions,
    cgm.total_deaths,
    cgm.mortality_rate,
    cgm.mean_los_days,
    cgm.avg_critical_lab_events
FROM control_group_metrics cgm;