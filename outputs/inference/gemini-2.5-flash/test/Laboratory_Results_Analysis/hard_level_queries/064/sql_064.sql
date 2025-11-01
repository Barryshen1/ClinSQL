WITH AdmissionsFiltered AS (
    -- Base cohort: Female inpatients, 65-75 years old
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        pat.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ad.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 65 AND 75
),
AcutePancreatitisAdmissionsOnly AS (
    -- Identify hadm_ids that have an acute pancreatitis diagnosis
    SELECT DISTINCT
        af.hadm_id
    FROM
        AdmissionsFiltered af
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON af.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
        ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
    WHERE
        d_icd.long_title LIKE '%acute pancreatitis%'
),
AcutePancreatitisCohort AS (
    -- Full admission details for the target cohort
    SELECT
        af.subject_id,
        af.hadm_id,
        af.admittime,
        af.dischtime,
        af.hospital_expire_flag
    FROM
        AdmissionsFiltered af
    INNER JOIN
        AcutePancreatitisAdmissionsOnly apa ON af.hadm_id = apa.hadm_id
),
LabInstabilityScores AS (
    -- Calculate first-48-hour lab instability score and critical lab flag for the target cohort
    SELECT
        apc.subject_id,
        apc.hadm_id,
        apc.admittime,
        apc.dischtime,
        apc.hospital_expire_flag,
        DATETIME_DIFF(apc.dischtime, apc.admittime, HOUR) / 24.0 AS los_days,
        COUNT(le.labevent_id) AS instability_score, -- Count of abnormal lab events in first 48h
        MAX(CASE WHEN le.labevent_id IS NOT NULL THEN 1 ELSE 0 END) AS has_critical_lab_48hr -- 1 if at least one abnormal lab event, 0 otherwise
    FROM
        AcutePancreatitisCohort apc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON apc.subject_id = le.subject_id
        AND apc.hadm_id = le.hadm_id
        AND le.charttime BETWEEN apc.admittime AND DATETIME_ADD(apc.admittime, INTERVAL 48 HOUR)
        AND le.flag = 'abnormal' -- Filter for abnormal lab events
    GROUP BY
        apc.subject_id, apc.hadm_id, apc.admittime, apc.dischtime, apc.hospital_expire_flag
),
QuintileData AS (
    -- Stratify the target cohort into quintiles based on instability score
    SELECT
        hadm_id,
        instability_score,
        los_days,
        hospital_expire_flag,
        has_critical_lab_48hr,
        NTILE(5) OVER (ORDER BY instability_score) AS instability_quintile
    FROM
        LabInstabilityScores
),
AgeMatchedComparisonCohort AS (
    -- Select age-matched inpatients (Female, 65-75) who DO NOT have acute pancreatitis
    SELECT
        af.subject_id,
        af.hadm_id,
        af.admittime,
        af.dischtime
    FROM
        AdmissionsFiltered af
    LEFT JOIN
        AcutePancreatitisAdmissionsOnly apa
        ON af.hadm_id = apa.hadm_id
    WHERE
        apa.hadm_id IS NULL -- Exclude admissions identified as acute pancreatitis
),
AgeMatchedLabData AS (
    -- Determine if age-matched comparison patients had critical labs in first 48 hours
    SELECT
        amc.hadm_id,
        MAX(CASE WHEN le.labevent_id IS NOT NULL THEN 1 ELSE 0 END) AS has_critical_lab_48hr_comparison
    FROM
        AgeMatchedComparisonCohort amc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON amc.subject_id = le.subject_id
        AND amc.hadm_id = le.hadm_id
        AND le.charttime BETWEEN amc.admittime AND DATETIME_ADD(amc.admittime, INTERVAL 48 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        amc.hadm_id
),
ComparisonCriticalLabPercentage AS (
    -- Calculate overall percentage of critical labs for the age-matched comparison cohort
    SELECT
        SUM(has_critical_lab_48hr_comparison) * 100.0 / COUNT(hadm_id) AS perc_critical_labs_age_matched
    FROM
        AgeMatchedLabData
)
-- Final SELECT statement to combine all calculated metrics per quintile
SELECT
    qd.instability_quintile,
    COUNT(qd.hadm_id) AS patient_count_target_cohort,
    CAST(AVG(qd.instability_score) AS BIGNUMERIC) AS mean_instability_score,
    CAST(AVG(qd.los_days) AS BIGNUMERIC) AS mean_los_days,
    CAST(SUM(qd.hospital_expire_flag) * 100.0 / COUNT(qd.hadm_id) AS BIGNUMERIC) AS mortality_percentage_target_cohort,
    -- Percentage with critical labs within the target cohort (per quintile)
    CAST(SUM(qd.has_critical_lab_48hr) * 100.0 / COUNT(qd.hadm_id) AS BIGNUMERIC) AS perc_critical_labs_target_cohort,
    -- Percentage with critical labs from the age-matched comparison group (overall value)
    (SELECT perc_critical_labs_age_matched FROM ComparisonCriticalLabPercentage) AS perc_critical_labs_age_matched_inpatients
FROM
    QuintileData qd
GROUP BY
    qd.instability_quintile
ORDER BY
    qd.instability_quintile;