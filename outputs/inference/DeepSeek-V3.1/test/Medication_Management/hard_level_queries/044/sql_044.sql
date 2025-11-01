WITH pe_admissions AS (
    SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 64 AND 74
        AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'I26%') 
            OR (di.icd_version = 9 AND di.icd_code LIKE '4151%')
        )
),

meds_input AS (
    SELECT ie.hadm_id, CAST(ie.itemid AS STRING) AS med_id
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    INNER JOIN pe_admissions pa
        ON ie.hadm_id = pa.hadm_id
    WHERE ie.starttime BETWEEN pa.admittime AND DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
),

meds_emar AS (
    SELECT e.hadm_id, e.medication AS med_id
    FROM `physionet-data.mimiciv_3_1_hosp.emar` e
    INNER JOIN pe_admissions pa
        ON e.hadm_id = pa.hadm_id
    WHERE e.scheduletime BETWEEN pa.admittime AND DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
),

meds_prescriptions AS (
    SELECT pr.hadm_id, pr.drug AS med_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN pe_admissions pa
        ON pr.hadm_id = pa.hadm_id
    WHERE pr.starttime BETWEEN pa.admittime AND DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
),

all_meds AS (
    SELECT hadm_id, med_id FROM meds_input
    UNION DISTINCT
    SELECT hadm_id, med_id FROM meds_emar
    UNION DISTINCT
    SELECT hadm_id, med_id FROM meds_prescriptions
),

med_count AS (
    SELECT 
        pa.*,
        COUNT(DISTINCT am.med_id) AS num_meds
    FROM pe_admissions pa
    LEFT JOIN all_meds am
        ON pa.hadm_id = am.hadm_id
    GROUP BY pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.hospital_expire_flag
),

tertiles AS (
    SELECT 
        *,
        NTILE(3) OVER (ORDER BY num_meds) AS tertile
    FROM med_count
),

readmissions AS (
    SELECT 
        t1.hadm_id,
        COUNT(t2.hadm_id) > 0 AS readmitted_30d
    FROM tertiles t1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` t2
        ON t1.subject_id = t2.subject_id
        AND t2.admittime > t1.dischtime
        AND t2.admittime <= DATETIME_ADD(t1.dischtime, INTERVAL 30 DAY)
        AND t2.hadm_id != t1.hadm_id
    GROUP BY t1.hadm_id
)

SELECT 
    tertile,
    COUNT(*) AS admissions,
    MIN(num_meds) AS min_meds,
    MAX(num_meds) AS max_meds,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los,
    AVG(hospital_expire_flag) * 100 AS mortality_pct,
    AVG(CAST(readmitted_30d AS INT)) * 100 AS readmission_30d_pct
FROM tertiles t
LEFT JOIN readmissions r
    ON t.hadm_id = r.hadm_id
GROUP BY tertile
ORDER BY tertile;