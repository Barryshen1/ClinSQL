WITH stroke_cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        CASE 
            WHEN diag.icd_version = 9 AND diag.icd_code LIKE '433%' THEN 'ischemic'
            WHEN diag.icd_version = 9 AND diag.icd_code LIKE '434%' THEN 'ischemic'
            WHEN diag.icd_version = 10 AND diag.icd_code LIKE 'I63%' THEN 'ischemic'
            WHEN diag.icd_version = 9 AND diag.icd_code LIKE '430%' THEN 'hemorrhagic'
            WHEN diag.icd_version = 9 AND diag.icd_code LIKE '431%' THEN 'hemorrhagic'
            WHEN diag.icd_version = 9 AND diag.icd_code LIKE '432%' THEN 'hemorrhagic'
            WHEN diag.icd_version = 10 AND diag.icd_code LIKE 'I60%' THEN 'hemorrhagic'
            WHEN diag.icd_version = 10 AND diag.icd_code LIKE 'I61%' THEN 'hemorrhagic'
            WHEN diag.icd_version = 10 AND diag.icd_code LIKE 'I62%' THEN 'hemorrhagic'
        END AS stroke_type,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        (SELECT COUNT(DISTINCT d2.icd_code) 
         FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
         WHERE d2.subject_id = adm.subject_id AND d2.hadm_id = adm.hadm_id
            AND NOT (
                (d2.icd_version = 9 AND (d2.icd_code LIKE '433%' OR d2.icd_code LIKE '434%' OR d2.icd_code LIKE '430%' OR d2.icd_code LIKE '431%' OR d2.icd_code LIKE '432%'))
                OR (d2.icd_version = 10 AND (d2.icd_code LIKE 'I63%' OR d2.icd_code LIKE 'I60%' OR d2.icd_code LIKE 'I61%' OR d2.icd_code LIKE 'I62%'))
            )
        ) AS comorbidity_count
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 44 AND 54
        AND (
            (diag.icd_version = 9 AND (diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' OR diag.icd_code LIKE '430%' OR diag.icd_code LIKE '431%' OR diag.icd_code LIKE '432%'))
            OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I63%' OR diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%'))
        )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY adm.hadm_id ORDER BY diag.seq_num) = 1
),

cohort_with_comorbidity AS (
    SELECT *,
        CASE 
            WHEN comorbidity_count < 5 THEN 'low'
            WHEN comorbidity_count < 10 THEN 'medium'
            ELSE 'high'
        END AS comorbidity_group
    FROM stroke_cohort
    WHERE stroke_type IS NOT NULL
),

vent AS (
    SELECT 
        ie.hadm_id,
        MAX(1) AS had_vent
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON pe.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON pe.itemid = di.itemid
    WHERE di.label LIKE '%ventilation%' OR di.label LIKE '%mechanical vent%'
    GROUP BY ie.hadm_id
),

vasopressor AS (
    SELECT 
        ie.hadm_id,
        MAX(1) AS had_vasopressor
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
        ON ie.stay_id = ic.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ie.itemid = di.itemid
    WHERE di.label LIKE '%norepinephrine%' OR di.label LIKE '%epinephrine%' OR di.label LIKE '%vasopressin%' OR di.label LIKE '%phenylephrine%' OR di.label LIKE '%dopamine%'
    GROUP BY ie.hadm_id
),

rrt AS (
    SELECT 
        ie.hadm_id,
        MAX(1) AS had_rrt
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON pe.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON pe.itemid = di.itemid
    WHERE di.label LIKE '%dialysis%' OR di.label LIKE '%CRRT%' OR di.label LIKE '%renal replacement%'
    GROUP BY ie.hadm_id
)

SELECT 
    c.stroke_type,
    CASE WHEN c.los_days <= 5 THEN '<=5' ELSE '>5' END AS los_group,
    c.comorbidity_group,
    COUNT(*) AS n_patients,
    AVG(c.hospital_expire_flag) * 100 AS mortality_percent,
    APPROX_QUANTILES(c.los_days, 100)[OFFSET(50)] AS median_los,
    AVG(COALESCE(v.had_vent, 0)) * 100 AS vent_percent,
    AVG(COALESCE(vs.had_vasopressor, 0)) * 100 AS vasopressor_percent,
    AVG(COALESCE(r.had_rrt, 0)) * 100 AS rrt_percent
FROM cohort_with_comorbidity c
LEFT JOIN vent v ON c.hadm_id = v.hadm_id
LEFT JOIN vasopressor vs ON c.hadm_id = vs.hadm_id
LEFT JOIN rrt r ON c.hadm_id = r.hadm_id
GROUP BY c.stroke_type, los_group, c.comorbidity_group
ORDER BY c.stroke_type, los_group, c.comorbidity_group;