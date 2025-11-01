WITH cohort AS (
    SELECT DISTINCT
        p.subject_id, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        i.stay_id,
        i.intime,
        i.outtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE p.anchor_age BETWEEN 80 AND 90
        AND p.gender = 'M'
        AND (
            (d.icd_version = 9 AND d.icd_code LIKE '038%') OR
            (d.icd_version = 9 AND d.icd_code = '99591') OR
            (d.icd_version = 9 AND d.icd_code = '99592') OR
            (d.icd_version = 10 AND d.icd_code LIKE 'A41%') OR
            (d.icd_version = 10 AND d.icd_code LIKE 'R65.2%')
        )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) = 1
),

drugs_first_24h AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        ie.itemid,
        di.label AS drug_name,
        ie.starttime
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
        ON c.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ie.itemid = di.itemid
    WHERE ie.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),

qt_drugs AS (
    SELECT DISTINCT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE 
        LOWER(label) LIKE '%amiodarone%' OR
        LOWER(label) LIKE '%sotalol%' OR
        LOWER(label) LIKE '%haloperidol%' OR
        LOWER(label) LIKE '%quinidine%' OR
        LOWER(label) LIKE '%disopyramide%' OR
        LOWER(label) LIKE '%dofetilide%' OR
        LOWER(label) LIKE '%ibutilide%' OR
        LOWER(label) LIKE '%procainamide%'
),

bleeding_drugs AS (
    SELECT DISTINCT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE 
        LOWER(label) LIKE '%warfarin%' OR
        LOWER(label) LIKE '%heparin%' OR
        LOWER(label) LIKE '%enoxaparin%' OR
        LOWER(label) LIKE '%dabigatran%' OR
        LOWER(label) LIKE '%rivaroxaban%' OR
        LOWER(label) LIKE '%apixaban%' OR
        LOWER(label) LIKE '%clopidogrel%' OR
        LOWER(label) LIKE '%ticagrelor%' OR
        LOWER(label) LIKE '%prasugrel%'
),

patients_qt AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM drugs_first_24h
    WHERE itemid IN (SELECT itemid FROM qt_drugs)
),

patients_bleeding AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM drugs_first_24h
    WHERE itemid IN (SELECT itemid FROM bleeding_drugs)
),

patients_both AS (
    SELECT subject_id, hadm_id
    FROM patients_qt
    INTERSECT DISTINCT
    SELECT subject_id, hadm_id
    FROM patients_bleeding
),

med_complexity AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        COUNT(DISTINCT d.itemid) AS num_drugs,
        CASE 
            WHEN pb.subject_id IS NOT NULL THEN 'Both QT and Bleeding'
            ELSE 'Other'
        END AS group_category
    FROM cohort c
    LEFT JOIN drugs_first_24h d
        ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
    LEFT JOIN patients_both pb
        ON c.subject_id = pb.subject_id AND c.hadm_id = pb.hadm_id
    GROUP BY c.subject_id, c.hadm_id, pb.subject_id
),

percentiles AS (
    SELECT 
        group_category,
        COUNT(*) AS n_patients,
        MIN(num_drugs) AS min_drugs,
        MAX(num_drugs) AS max_drugs,
        AVG(num_drugs) AS avg_drugs,
        PERCENTILE_CONT(num_drugs, 0.75) OVER (PARTITION BY group_category) AS p75
    FROM med_complexity
    GROUP BY group_category, num_drugs
),

top_quartile_patients AS (
    SELECT 
        mc.subject_id,
        mc.hadm_id,
        mc.group_category,
        mc.num_drugs
    FROM med_complexity mc
    INNER JOIN (
        SELECT DISTINCT group_category, p75
        FROM percentiles
    ) p
        ON mc.group_category = p.group_category
    WHERE mc.num_drugs >= p.p75
)

SELECT 
    tqp.group_category,
    COUNT(*) AS n_patients,
    AVG(DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0) AS avg_los_days,
    SUM(c.hospital_expire_flag) AS mortality_count,
    AVG(c.hospital_expire_flag) AS mortality_rate
FROM top_quartile_patients tqp
INNER JOIN cohort c
    ON tqp.subject_id = c.subject_id AND tqp.hadm_id = c.hadm_id
GROUP BY tqp.group_category;