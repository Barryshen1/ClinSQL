WITH Admissions_Age AS (
    -- Calculate age at admission for all patients
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        pat.gender,
        EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
),
Stroke_Diagnosis AS (
    -- Identify admissions with an acute ischemic stroke diagnosis (ICD-9: 434.x, ICD-10: I63.x)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND STARTS_WITH(icd_code, 'I63')) -- ICD-10 for cerebral infarction (ischemic stroke)
        OR (icd_version = 9 AND STARTS_WITH(icd_code, '434')) -- ICD-9 for cerebral infarction (ischemic stroke)
),
Target_Stroke_Cohort_Admissions AS (
    -- Define the specific cohort: female patients aged 78-88 with acute ischemic stroke
    SELECT
        aa.subject_id,
        aa.hadm_id,
        aa.admittime,
        aa.dischtime,
        aa.hospital_expire_flag,
        aa.gender,
        aa.age_at_admission
    FROM Admissions_Age aa
    INNER JOIN Stroke_Diagnosis sd ON aa.hadm_id = sd.hadm_id
    WHERE
        aa.gender = 'F'
        AND aa.age_at_admission BETWEEN 78 AND 88
),
Critical_Lab_Events_Within_72h_Raw AS (
    -- Identify all critical lab events within the first 72 hours of *any* admission
    SELECT
        le.hadm_id,
        le.labevent_id -- labevent_id is unique per observation
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON le.hadm_id = adm.hadm_id
    WHERE
        le.valuenum IS NOT NULL
        -- FIXED: Reference ranges are in labevents (le), not d_labitems (dli)
        AND le.ref_range_lower IS NOT NULL
        AND le.ref_range_upper IS NOT NULL
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
        AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
),
All_Admissions_Critical_Lab_Counts AS (
    -- Count critical lab events per admission for all admissions (including those with zero critical labs)
    SELECT
        adm.hadm_id,
        -- Count distinct labevent_ids that meet critical criteria within 72 hours
        COALESCE(COUNT(cle.labevent_id), 0) AS critical_lab_count_72h
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    LEFT JOIN
        Critical_Lab_Events_Within_72h_Raw cle ON adm.hadm_id = cle.hadm_id
    GROUP BY
        adm.hadm_id
),
Stroke_Cohort_With_Labs_LOS_Mortality AS (
    -- Combine the target stroke cohort details with their critical lab counts, LOS, and mortality
    SELECT
        tsc.subject_id,
        tsc.hadm_id,
        tsc.admittime,
        tsc.dischtime,
        tsc.hospital_expire_flag,
        tsc.age_at_admission,
        aalcc.critical_lab_count_72h,
        DATE_DIFF(tsc.dischtime, tsc.admittime, HOUR) / 24.0 AS los_days
    FROM Target_Stroke_Cohort_Admissions tsc
    LEFT JOIN All_Admissions_Critical_Lab_Counts aalcc ON tsc.hadm_id = aalcc.hadm_id
)
-- Final selection: calculate required metrics
SELECT
    -- Minimum 72-hour laboratory instability score for the cohort
    MIN(src.critical_lab_count_72h) AS min_72h_lab_instability_score_cohort,

    -- Average 72-hour laboratory instability score (critical lab events) for the cohort
    AVG(src.critical_lab_count_72h) AS avg_72h_lab_instability_score_cohort,

    -- Average 72-hour critical lab events for general inpatients (for comparison)
    (SELECT AVG(critical_lab_count_72h) FROM All_Admissions_Critical_Lab_Counts) AS avg_72h_critical_labs_general_inpatients,

    -- Average length of stay (in days) for the cohort
    AVG(src.los_days) AS avg_los_cohort_days,

    -- In-hospital mortality rate (%) for the cohort
    SUM(CASE WHEN src.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(src.hadm_id) AS in_hospital_mortality_rate_cohort
FROM Stroke_Cohort_With_Labs_LOS_Mortality src;