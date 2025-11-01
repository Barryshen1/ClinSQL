WITH FemaleAMIDemographics AS (
    -- Step 1: Identify Female AMI admissions aged 90-100+
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age >= 90 -- MIMIC-IV caps age at 91 for 90+ years old. We interpret "90-100" as 90+.
        AND EXISTS (
            -- Check for AMI (Acute Myocardial Infarction) diagnoses
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            WHERE
                di.hadm_id = ad.hadm_id
                AND (
                    -- ICD-9 codes for AMI (410.x)
                    (di.icd_version = 9 AND di.icd_code LIKE '410%')
                    OR
                    -- ICD-10 codes for AMI (I21.x excluding I21.9 for unspecified)
                    (di.icd_version = 10 AND di.icd_code LIKE 'I21%' AND NOT di.icd_code LIKE 'I219%')
                )
        )
),
FemaleAMILabScores AS (
    -- Step 2: Calculate Lab Instability Score for Female AMI admissions
    -- Lab instability score = count of distinct lab itemids with out-of-range values in first 48 hours
    SELECT
        fami.subject_id,
        fami.hadm_id,
        fami.admittime,
        fami.dischtime,
        fami.hospital_expire_flag,
        COUNT(DISTINCT CASE
            WHEN
                le.valuenum IS NOT NULL -- Must have a numeric value
                AND (
                    (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                    OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
                )
            THEN le.itemid
            ELSE NULL
        END) AS lab_instability_score_48hr
    FROM
        FemaleAMIDemographics AS fami
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON fami.subject_id = le.subject_id
        AND fami.hadm_id = le.hadm_id
        AND le.charttime BETWEEN fami.admittime AND DATETIME_ADD(fami.admittime, INTERVAL 48 HOUR)
    GROUP BY
        fami.subject_id, fami.hadm_id, fami.admittime, fami.dischtime, fami.hospital_expire_flag
),
P75_FemaleAMILabInstability AS (
    -- Step 3: Calculate the 75th percentile of the lab instability score for Female AMI patients
    SELECT
        PERCENTILE_CONT(lab_instability_score_48hr, 0.75) OVER() AS p75_score
    FROM
        FemaleAMILabScores
    QUALIFY ROW_NUMBER() OVER(ORDER BY 1) = 1 -- Ensures only one row for the P75 score
),
HighInstabilityFemaleAMIMetrics AS (
    -- Step 4: Report metrics for Female AMI patients with lab instability >= P75
    SELECT
        'Female AMI 90+ (>= P75 Lab Instability)' AS cohort_description,
        COUNT(DISTINCT fals.hadm_id) AS num_admissions,
        SUM(fals.hospital_expire_flag) AS in_hospital_mortality_count,
        AVG(fals.hospital_expire_flag) AS in_hospital_mortality_rate,
        AVG(DATETIME_DIFF(fals.dischtime, fals.admittime, HOUR) / 24.0) AS mean_los_days,
        AVG(fals.lab_instability_score_48hr) AS mean_critical_lab_rate -- interpreted as mean lab instability score
    FROM
        FemaleAMILabScores AS fals, P75_FemaleAMILabInstability AS p75
    WHERE
        fals.lab_instability_score_48hr >= p75.p75_score
),
All90PlusDemographics AS (
    -- Step 5: Identify all inpatient admissions aged 90-100+ for comparison
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.anchor_age >= 90
),
All90PlusLabScores AS (
    -- Step 6: Calculate Lab Instability Score for all 90+ inpatient admissions
    SELECT
        aplus.subject_id,
        aplus.hadm_id,
        aplus.admittime,
        aplus.dischtime,
        aplus.hospital_expire_flag,
        COUNT(DISTINCT CASE
            WHEN
                le.valuenum IS NOT NULL -- Must have a numeric value
                AND (
                    (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                    OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
                )
            THEN le.itemid
            ELSE NULL
        END) AS lab_instability_score_48hr
    FROM
        All90PlusDemographics AS aplus
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON aplus.subject_id = le.subject_id
        AND aplus.hadm_id = le.hadm_id
        AND le.charttime BETWEEN aplus.admittime AND DATETIME_ADD(aplus.admittime, INTERVAL 48 HOUR)
    GROUP BY
        aplus.subject_id, aplus.hadm_id, aplus.admittime, aplus.dischtime, aplus.hospital_expire_flag
),
All90PlusMetrics AS (
    -- Step 7: Report metrics for all 90+ inpatient admissions
    SELECT
        'All Inpatients 90+' AS cohort_description,
        COUNT(DISTINCT apls.hadm_id) AS num_admissions,
        SUM(apls.hospital_expire_flag) AS in_hospital_mortality_count,
        AVG(apls.hospital_expire_flag) AS in_hospital_mortality_rate,
        AVG(DATETIME_DIFF(apls.dischtime, apls.admittime, HOUR) / 24.0) AS mean_los_days,
        AVG(apls.lab_instability_score_48hr) AS mean_critical_lab_rate -- interpreted as mean lab instability score
    FROM
        All90PlusLabScores AS apls
)
-- Step 8: Combine and present the results
SELECT * FROM HighInstabilityFemaleAMIMetrics
UNION ALL
SELECT * FROM All90PlusMetrics;