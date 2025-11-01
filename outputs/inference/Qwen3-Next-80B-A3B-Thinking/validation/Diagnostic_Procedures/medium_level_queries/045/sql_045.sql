WITH dvt_admissions AS (
    SELECT a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 78 AND 88
      AND (d_diag.long_title LIKE '%deep vein thrombosis%' OR d_diag.long_title LIKE '%DVT%')
),
icu_status AS (
    SELECT a.hadm_id,
           CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END as has_icu
    FROM dvt_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
),
noninvasive_counts AS (
    SELECT a.hadm_id,
           COALESCE(lab_count, 0) + COALESCE(proc_count, 0) as noninvasive_count
    FROM dvt_admissions a
    LEFT JOIN (
        SELECT hadm_id, COUNT(*) as lab_count
        FROM `physionet-data.mimiciv_3_1_hosp.labevents`
        WHERE itemid = 50912
        GROUP BY hadm_id
    ) l ON a.hadm_id = l.hadm_id
    LEFT JOIN (
        SELECT hadm_id, COUNT(*) as proc_count
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
        WHERE itemid = 225800
        GROUP BY hadm_id
    ) p ON a.hadm_id = p.hadm_id
),
los_calc AS (
    SELECT 
        i.hadm_id,
        i.has_icu,
        n.noninvasive_count,
        DATE_DIFF(a.dischtime, a.admittime, DAY) as los_days
    FROM icu_status i
    JOIN dvt_admissions a ON i.hadm_id = a.hadm_id
    JOIN noninvasive_counts n ON i.hadm_id = n.hadm_id
)
SELECT 
    CASE 
        WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END as los_group,
    has_icu,
    COUNT(*) as admission_count,
    AVG(noninvasive_count) as mean_noninvasive
FROM los_calc
WHERE los_days BETWEEN 1 AND 8
GROUP BY los_group, has_icu;