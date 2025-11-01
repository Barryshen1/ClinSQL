WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.anchor_age BETWEEN 65 AND 75
        AND pat.gender = 'F'
        AND adm.dischtime IS NOT NULL
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 96
        AND adm.hadm_id IN (
            SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE icd_code LIKE 'E11%' AND icd_version = 10
        )
        AND adm.hadm_id IN (
            SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE icd_code LIKE 'I50%' AND icd_version = 10
        )
),

insulin_events AS (
    SELECT 
        ie.subject_id,
        ie.hadm_id,
        ie.starttime,
        ie.itemid,
        di.label,
        CASE 
            WHEN di.itemid IN (221744, 221749) THEN 'basal'
            WHEN di.itemid IN (221835, 221834) THEN 'bolus'
            ELSE 'other'
        END AS insulin_type
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    INNER JOIN cohort c
        ON ie.hadm_id = c.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ie.itemid = di.itemid
    WHERE di.category LIKE '%Insulin%'
),

early_insulin AS (
    SELECT 
        subject_id,
        hadm_id,
        MAX(CASE WHEN insulin_type = 'basal' THEN 1 ELSE 0 END) AS basal_early,
        MAX(CASE WHEN insulin_type = 'bolus' THEN 1 ELSE 0 END) AS bolus_early
    FROM insulin_events
    WHERE starttime BETWEEN (SELECT admittime FROM cohort WHERE cohort.hadm_id = insulin_events.hadm_id) 
        AND DATETIME_ADD((SELECT admittime FROM cohort WHERE cohort.hadm_id = insulin_events.hadm_id), INTERVAL 48 HOUR)
    GROUP BY subject_id, hadm_id
),

late_insulin AS (
    SELECT 
        subject_id,
        hadm_id,
        MAX(CASE WHEN insulin_type = 'basal' THEN 1 ELSE 0 END) AS basal_late,
        MAX(CASE WHEN insulin_type = 'bolus' THEN 1 ELSE 0 END) AS bolus_late
    FROM insulin_events
    WHERE starttime BETWEEN DATETIME_SUB((SELECT dischtime FROM cohort WHERE cohort.hadm_id = insulin_events.hadm_id), INTERVAL 48 HOUR) 
        AND (SELECT dischtime FROM cohort WHERE cohort.hadm_id = insulin_events.hadm_id)
    GROUP BY subject_id, hadm_id
),

regimens_early AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        CASE 
            WHEN ei.basal_early = 1 AND ei.bolus_early = 0 THEN 'basal_only'
            WHEN ei.basal_early = 0 AND ei.bolus_early = 1 THEN 'bolus_only'
            WHEN ei.basal_early = 1 AND ei.bolus_early = 1 THEN 'basal_bolus'
            ELSE 'none'
        END AS regimen_early
    FROM cohort c
    LEFT JOIN early_insulin ei
        ON c.hadm_id = ei.hadm_id AND c.subject_id = ei.subject_id
),

regimens_late AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        CASE 
            WHEN li.basal_late = 1 AND li.bolus_late = 0 THEN 'basal_only'
            WHEN li.basal_late = 0 AND li.bolus_late = 1 THEN 'bolus_only'
            WHEN li.basal_late = 1 AND li.bolus_late = 1 THEN 'basal_bolus'
            ELSE 'none'
        END AS regimen_late
    FROM cohort c
    LEFT JOIN late_insulin li
        ON c.hadm_id = li.hadm_id AND c.subject_id = li.subject_id
)

SELECT 
    regimen_early,
    regimen_late,
    COUNT(*) AS num_patients,
    ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM cohort), 2) AS percentage
FROM (
    SELECT 
        re.regimen_early,
        rl.regimen_late
    FROM regimens_early re
    INNER JOIN regimens_late rl
        ON re.hadm_id = rl.hadm_id AND re.subject_id = rl.subject_id
)
GROUP BY regimen_early, regimen_late
ORDER BY regimen_early, regimen_late;