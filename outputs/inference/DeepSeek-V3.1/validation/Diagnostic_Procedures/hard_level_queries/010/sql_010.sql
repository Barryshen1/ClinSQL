WITH cohort AS (
    SELECT 
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        p.gender,
        p.anchor_age,
        adm.hospital_expire_flag,
        -- Flag for hemorrhagic stroke: ICD-10: I60, I61, I62; ICD-9: 430, 431, 432
        MAX(CASE 
            WHEN di.icd_code LIKE 'I6[0-2]%' OR di.icd_code IN ('430', '431', '432') 
            THEN 1 
            ELSE 0 
        END) AS hemorrhagic_stroke
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ie.hadm_id = di.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 40 AND 50
    GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime, ie.outtime, ie.los, p.gender, p.anchor_age, adm.hospital_expire_flag
),

procedures_in_72h AS (
    SELECT 
        c.stay_id,
        COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON c.stay_id = pe.stay_id
        AND pe.starttime >= c.intime
        AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    GROUP BY c.stay_id
)

SELECT 
    c.hemorrhagic_stroke,
    COUNT(*) AS num_patients,
    -- 90th percentile of diagnostic procedures
    APPROX_QUANTILES(p.num_procedures, 100)[OFFSET(90)] AS proc_90th_percentile,
    -- 90th percentile of ICU LOS
    APPROX_QUANTILES(c.los, 100)[OFFSET(90)] AS los_90th_percentile,
    -- In-hospital mortality rate
    ROUND(100.0 * SUM(c.hospital_expire_flag) / COUNT(*), 2) AS mortality_percent
FROM cohort c
LEFT JOIN procedures_in_72h p
    ON c.stay_id = p.stay_id
GROUP BY c.hemorrhagic_stroke
ORDER BY c.hemorrhagic_stroke;