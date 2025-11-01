WITH dka_hadm AS (
    SELECT di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE d.long_title LIKE '%ketoacidosis%'
),

eligible_patients AS (
    SELECT p.subject_id, p.anchor_age, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND a.hadm_id IN (SELECT hadm_id FROM dka_hadm)
),

first_icu_stay AS (
    SELECT 
        i.stay_id, 
        i.hadm_id, 
        i.intime, 
        i.los,
        ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    WHERE i.hadm_id IN (SELECT hadm_id FROM eligible_patients)
),

procedures_count AS (
    SELECT 
        f.stay_id, 
        f.hadm_id, 
        f.intime,
        f.los,
        COUNT(DISTINCT pe.itemid) AS proc_count
    FROM first_icu_stay f
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.stay_id = pe.stay_id
    WHERE f.rn = 1
    AND pe.starttime >= f.intime
    AND pe.starttime <= f.intime + INTERVAL 24 HOUR
    GROUP BY f.stay_id, f.hadm_id, f.intime, f.los
),

hospital_mortality AS (
    SELECT a.hadm_id, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    WHERE a.hadm_id IN (SELECT hadm_id FROM eligible_patients)
),

final_data AS (
    SELECT 
        p.proc_count,
        p.los,
        h.hospital_expire_flag
    FROM procedures_count p
    JOIN hospital_mortality h ON p.hadm_id = h.hadm_id
),

quintiles AS (
    SELECT 
        proc_count,
        los,
        hospital_expire_flag,
        NTILE(5) OVER (ORDER BY proc_count) AS quintile
    FROM final_data
)

SELECT 
    quintile,
    COUNT(*) AS num_stays,
    AVG(proc_count) AS mean_proc_count,
    MIN(proc_count) AS min_proc_count,
    MAX(proc_count) AS max_proc_count,
    AVG(los) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_pct
FROM quintiles
GROUP BY quintile
ORDER BY quintile;