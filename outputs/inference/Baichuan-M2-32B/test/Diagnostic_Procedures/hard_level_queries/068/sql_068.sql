WITH eligible_patients AS (
    SELECT
        subject_id,
        anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
        AND anchor_age BETWEEN 77 AND 87
),
asthma_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.subject_id = d.subject_id
        AND a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
    WHERE dd.long_title LIKE '%asthma%'
        AND (dd.long_title LIKE '%exacerbation%' OR dd.long_title LIKE '%status asthmaticus%')
        AND a.subject_id IN (SELECT subject_id FROM eligible_patients)
    GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
icu_stays AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN asthma_admissions a
        ON i.subject_id = a.subject_id
        AND i.hadm_id = a.hadm_id
),
first72h_procedures AS (
    SELECT
        s.subject_id,
        s.hadm_id,
        s.stay_id,
        COUNT(*) AS procedure_count
    FROM icu_stays s
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
        ON s.subject_id = p.subject_id
        AND s.hadm_id = p.hadm_id
        AND s.stay_id = p.stay_id
        AND p.starttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
    GROUP BY s.subject_id, s.hadm_id, s.stay_id
),
cohort AS (
    SELECT
        s.subject_id,
        s.hadm_id,
        s.stay_id,
        fp.procedure_count,
        DATE_DIFF(s.dischtime, s.admittime, DAY) AS los_days,
        s.hospital_expire_flag
    FROM icu_stays s
    INNER JOIN first72h_procedures fp
        ON s.subject_id = fp.subject_id
        AND s.hadm_id = fp.hadm_id
        AND s.stay_id = fp.stay_id
    WHERE s.dischtime IS NOT NULL
),
quartiles AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY procedure_count) AS quartile
    FROM cohort
)
SELECT
    quartile,
    AVG(procedure_count) AS mean_procedure_count,
    AVG(los_days) AS mean_los_days,
    AVG(hospital_expire_flag) AS hospital_mortality
FROM quartiles
GROUP BY quartile
ORDER BY quartile;