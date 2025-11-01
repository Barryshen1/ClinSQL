WITH asthma_admissions AS (
    SELECT d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE di.long_title LIKE '%asthma%' AND di.long_title LIKE '%exacerbation%'
),

patients_info AS (
    SELECT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 77 AND 87
        AND a.hadm_id IN (SELECT hadm_id FROM asthma_admissions)
),

los_calc AS (
    SELECT hadm_id, subject_id,
           TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
    FROM patients_info
),

icu_status AS (
    SELECT hadm_id,
           CASE WHEN COUNT(stay_id) > 0 THEN 'ICU' ELSE 'Non-ICU' END AS icu_group
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY hadm_id
),

ct_mri_counts AS (
    SELECT hadm_id, COUNT(*) AS ct_mri_count
    FROM (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` di
            ON p.icd_code = di.icd_code AND p.icd_version = di.icd_version
        WHERE di.long_title LIKE '%CT%' OR di.long_title LIKE '%MRI%'
        UNION ALL
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
            ON pe.itemid = di.itemid
        WHERE di.label LIKE '%CT%' OR di.label LIKE '%MRI%'
    ) AS combined
    GROUP BY hadm_id
)

SELECT 
    icu_group,
    CASE 
        WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    AVG(COALESCE(cmc.ct_mri_count, 0)) AS mean_ct_mri,
    MIN(COALESCE(cmc.ct_mri_count, 0)) AS min_ct_mri,
    MAX(COALESCE(cmc.ct_mri_count, 0)) AS max_ct_mri
FROM los_calc lc
JOIN icu_status isu ON lc.hadm_id = isu.hadm_id
LEFT JOIN ct_mri_counts cmc ON lc.hadm_id = cmc.hadm_id
WHERE los_days BETWEEN 1 AND 8
GROUP BY icu_group, los_group;