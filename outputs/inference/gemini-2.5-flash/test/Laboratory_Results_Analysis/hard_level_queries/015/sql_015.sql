WITH IschemicStrokeAdmissions AS (
    -- Step 1: Identify all male inpatients aged 49-59 with an ischemic stroke diagnosis
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_icd
        ON adm.hadm_id = diag_icd.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 49 AND 59
        AND (
            -- ICD-9 codes for ischemic stroke
            (diag_icd.icd_version = 9 AND (diag_icd.icd_code LIKE '433%' OR diag_icd.icd_code LIKE '434%' OR diag_icd.icd_code = '436'))
            OR
            -- ICD-10 codes for ischemic stroke
            (diag_icd.icd_version = 10 AND diag_icd.icd_code LIKE 'I63%')
        )
),
AllMaleAdmissions AS (
    -- Step 2: Identify all male inpatients aged 49-59 (used for controls and general context)
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 49 AND 59
),
LabInstabilityScoresRaw AS (
    -- Step 3: Calculate 72-hour lab instability score for all relevant admissions
    -- Score is defined as the count of distinct lab items with values outside reference range
    SELECT
        ama.subject_id,
        ama.hadm_id,
        COUNT(DISTINCT
            CASE
                WHEN le.valuenum IS NOT NULL
                AND dli.ref_range_lower IS NOT NULL
                AND dli.ref_range_upper IS NOT NULL
                AND (le.valuenum < dli.ref_range_lower OR le.valuenum > dli.ref_range_upper)
                THEN le.itemid
                ELSE NULL
            END
        ) AS lab_instability_score
    FROM AllMaleAdmissions ama
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ama.subject_id = le.subject_id
        AND ama.hadm_id = le.hadm_id
        AND le.charttime BETWEEN ama.admittime AND TIMESTAMP_ADD(ama.admittime, INTERVAL 72 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    GROUP BY ama.subject_id, ama.hadm_id
),
StrokeCohortInstability AS (
    -- Step 4: Combine stroke admissions with their calculated instability scores
    SELECT
        isa.subject_id,
        isa.hadm_id,
        isa.admittime,
        isa.dischtime,
        isa.hospital_expire_flag,
        COALESCE(lis.lab_instability_score, 0) AS lab_instability_score -- Treat NULL scores as 0
    FROM IschemicStrokeAdmissions isa
    LEFT JOIN LabInstabilityScoresRaw lis
        ON isa.subject_id = lis.subject_id
        AND isa.hadm_id = lis.hadm_id
),
P75ScoreCTE AS ( -- Renamed from 75thPercentileScore
    -- Step 5: Calculate the 75th percentile of the lab instability score for the stroke cohort
    SELECT
        PERCENTILE_CONT(0.75) OVER() AS p75_score
    FROM StrokeCohortInstability
),
HighInstabilityStrokeGroup AS (
    -- Step 6: Identify the high-instability stroke group
    SELECT
        sci.subject_id,
        sci.hadm_id,
        sci.admittime,
        sci.dischtime,
        sci.hospital_expire_flag
    FROM StrokeCohortInstability sci, P75ScoreCTE p75 -- Reference updated
    WHERE sci.lab_instability_score >= p75.p75_score
),
CriticalLabFlags AS (
    -- Step 7: Determine for each admission if there was any critical (flagged) lab event in the first 72 hours
    SELECT
        ama.subject_id,
        ama.hadm_id,
        MAX(CASE WHEN le.flag IS NOT NULL THEN 1 ELSE 0 END) AS has_critical_lab_72hr
    FROM AllMaleAdmissions ama
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ama.subject_id = le.subject_id
        AND ama.hadm_id = le.hadm_id
        AND le.charttime BETWEEN ama.admittime AND TIMESTAMP_ADD(ama.admittime, INTERVAL 72 HOUR)
    GROUP BY ama.subject_id, ama.hadm_id
)
-- Step 8: Final report assembling all requested metrics
SELECT
    '75th_Percentile_Lab_Instability_Score_Stroke_Group' AS metric,
    CAST(p75.p75_score AS STRING) AS value_or_description
FROM P75ScoreCTE p75 -- Reference updated

UNION ALL

SELECT
    'High_Instability_Stroke_Group_LOS_Days_Mean' AS metric,
    CAST(AVG(DATE_DIFF(his.dischtime, his.admittime, DAY)) AS STRING) AS value_or_description
FROM HighInstabilityStrokeGroup his

UNION ALL

SELECT
    'High_Instability_Stroke_Group_Mortality_Rate_Percent' AS metric,
    CAST(AVG(his.hospital_expire_flag) * 100 AS STRING) AS value_or_description
FROM HighInstabilityStrokeGroup his

UNION ALL

SELECT
    'High_Instability_Stroke_Group_Critical_Lab_Rate_Percent' AS metric,
    CAST(COALESCE(AVG(clf.has_critical_lab_72hr), 0) * 100 AS STRING) AS value_or_description
FROM HighInstabilityStrokeGroup his
LEFT JOIN CriticalLabFlags clf
    ON his.subject_id = clf.subject_id
    AND his.hadm_id = clf.hadm_id

UNION ALL

SELECT
    'Age_Matched_Control_Group_Critical_Lab_Rate_Percent' AS metric,
    CAST(COALESCE(AVG(clf.has_critical_lab_72hr), 0) * 100 AS STRING) AS value_or_description
FROM AllMaleAdmissions ama
LEFT JOIN IschemicStrokeAdmissions isa
    ON ama.subject_id = isa.subject_id
    AND ama.hadm_id = isa.hadm_id
LEFT JOIN CriticalLabFlags clf
    ON ama.subject_id = clf.subject_id
    AND ama.hadm_id = clf.hadm_id
WHERE
    isa.hadm_id IS NULL; -- Exclude stroke patients to form the control group;