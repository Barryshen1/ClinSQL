WITH acs_icd_codes AS (
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code = '4111')) -- ICD-9 codes for MI (410.x) and Unstable Angina (411.1)
        OR (icd_version = 10 AND (icd_code LIKE 'I20.0%' OR icd_code LIKE 'I21%' OR icd_code LIKE 'I22%')) -- ICD-10 codes for Unstable Angina (I20.0), STEMI (I21.x), NSTEMI (I21.x), Subsequent MI (I22.x)
),
-- Step 2: Create the initial ACS Male Inpatient Cohort (aged 87-97)
-- This CTE filters admissions for male patients aged 87-97 with any ACS diagnosis.
acs_cohort_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN acs_icd_codes AS acs_codes
        ON diag.icd_code = acs_codes.icd_code AND diag.icd_version = acs_codes.icd_version
    WHERE
        pat.gender = 'M'
        -- Calculate age at admission: anchor_age is age at anchor_year.
        -- We add the difference in years between admittime and anchor_year to anchor_age.
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 87 AND 97
    GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
),
-- Step 3: Calculate 72-hour critical lab events for the ACS cohort as the 'lab instability score'.
-- This CTE counts abnormal lab events ('flag' = 'abnormal') within the first 72 hours of admission
-- for each patient in the ACS cohort.
acs_cohort_lab_scores AS (
    SELECT
        aca.subject_id,
        aca.hadm_id,
        aca.admittime,
        aca.dischtime,
        aca.hospital_expire_flag,
        COUNT(le.labevent_id) AS lab_instability_score -- Counts events where flag is 'abnormal'
    FROM acs_cohort_admissions AS aca
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON aca.subject_id = le.subject_id
        AND aca.hadm_id = le.hadm_id
        AND le.charttime BETWEEN aca.admittime AND DATETIME_ADD(aca.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal' -- Filter for abnormal lab results
    GROUP BY aca.subject_id, aca.hadm_id, aca.admittime, aca.dischtime, aca.hospital_expire_flag
),
-- Step 4: Calculate the 95th percentile of the lab instability score within the ACS cohort.
percentile_95 AS (
    SELECT
        PERCENTILE_CONT(acls.lab_instability_score, 0.95) OVER() AS p95_lab_score
    FROM acs_cohort_lab_scores AS acls -- Added alias 'acls' here to reference the column
),
-- Step 5: Identify the 'High Instability Group' (those with scores >= P95) and calculate their statistics.
high_instability_group_stats AS (
    SELECT
        COUNT(DISTINCT acls.hadm_id) AS num_patients_high_instability,
        AVG(DATETIME_DIFF(acls.dischtime, acls.admittime, HOUR) / 24.0) AS mean_los_days,
        AVG(CASE WHEN acls.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS in_hospital_mortality_rate,
        AVG(acls.lab_instability_score) AS avg_critical_lab_events_high_instability_group
    FROM acs_cohort_lab_scores AS acls, percentile_95 AS p95 -- Cross join with percentile to use its value
    WHERE acls.lab_instability_score >= p95.p95_lab_score
),
-- Capture all HADM_IDs that are part of the ACS cohort to exclude them from the 'general inpatients' group.
all_acs_hadm_ids AS (
    SELECT DISTINCT hadm_id FROM acs_cohort_admissions
),
-- Step 6: Identify "General Inpatients" (all admissions *not* in the ACS cohort) and calculate their average lab events.
general_inpatients_lab_scores AS (
    SELECT
        adm.hadm_id,
        COUNT(le.labevent_id) AS general_lab_instability_score
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON adm.subject_id = le.subject_id
        AND adm.hadm_id = le.hadm_id
        AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal'
    WHERE adm.hadm_id NOT IN (SELECT hadm_id FROM all_acs_hadm_ids)
    GROUP BY adm.hadm_id
)
-- Final SELECT statement to present all calculated results.
SELECT
    p95.p95_lab_score AS percentile_95_lab_instability_score,
    his.num_patients_high_instability,
    his.mean_los_days,
    his.in_hospital_mortality_rate,
    his.avg_critical_lab_events_high_instability_group,
    AVG(gils.general_lab_instability_score) AS avg_critical_lab_events_general_inpatients
FROM percentile_95 AS p95,
     high_instability_group_stats AS his,
     -- Cross joining general_inpatients_lab_scores here will result in averaging all scores.
     -- If the intent was to compare the _average_ of general inpatients to the high instability group,
     -- then AVG(gils.general_lab_instability_score) is appropriate, which it is.
     general_inpatients_lab_scores AS gils
GROUP BY
    p95.p95_lab_score,
    his.num_patients_high_instability,
    his.mean_los_days,
    his.in_hospital_mortality_rate,
    his.avg_critical_lab_events_high_instability_group
;