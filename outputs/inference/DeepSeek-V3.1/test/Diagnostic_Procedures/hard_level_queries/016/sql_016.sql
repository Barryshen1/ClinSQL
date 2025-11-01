WITH first_icu_stays AS (
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        p.anchor_age,
        p.gender,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON ie.hadm_id = a.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 88 AND 98
        AND ie.intime = (
            SELECT MIN(ie2.intime)
            FROM `physionet-data.mimiciv_3_1_icu.icustays` ie2
            WHERE ie2.subject_id = ie.subject_id
        )
),
pneumonia_diagnoses AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE dd.long_title LIKE '%pneumonia%'
),
procedure_counts AS (
    SELECT
        fis.stay_id,
        COUNT(pe.itemid) AS procedure_count
    FROM first_icu_stays fis
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON fis.stay_id = pe.stay_id
        AND pe.starttime >= fis.intime
        AND pe.starttime <= DATETIME_ADD(fis.intime, INTERVAL 72 HOUR)
    WHERE fis.hadm_id IN (SELECT hadm_id FROM pneumonia_diagnoses)
    GROUP BY fis.stay_id
),
quintiles AS (
    SELECT
        stay_id,
        procedure_count,
        NTILE(5) OVER (ORDER BY procedure_count) AS quintile
    FROM procedure_counts
)
SELECT
    quintile,
    AVG(procedure_count) AS avg_procedure_count,
    AVG(fis.los) AS avg_icu_los_days,
    AVG(fis.hospital_expire_flag) * 100 AS mortality_pct
FROM quintiles q
INNER JOIN first_icu_stays fis
    ON q.stay_id = fis.stay_id
GROUP BY quintile
ORDER BY quintile;