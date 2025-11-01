WITH first_icustays AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        los AS icu_los_hours,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
eligible_patients AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.hospital_expire_flag,
        fi.stay_id,
        fi.intime,
        fi.icu_los_hours,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN first_icustays fi
        ON p.subject_id = fi.subject_id
        AND a.hadm_id = fi.hadm_id
        AND fi.rn = 1  -- first ICU stay
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 37 AND 47
        AND dd.long_title LIKE '%pneumonia%'
),
procedure_counts AS (
    SELECT
        ep.subject_id,
        ep.hadm_id,
        ep.stay_id,
        COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
    FROM eligible_patients ep
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON ep.subject_id = pe.subject_id
        AND ep.hadm_id = pe.hadm_id
        AND ep.stay_id = pe.stay_id
        AND pe.starttime BETWEEN ep.intime AND TIMESTAMP_ADD(ep.intime, INTERVAL 48 HOUR)
    GROUP BY ep.subject_id, ep.hadm_id, ep.stay_id
),
quintile_assignment AS (
    SELECT
        pc.subject_id,
        pc.distinct_procedure_count,
        ep.icu_los_hours,
        ep.hospital_expire_flag,
        NTILE(5) OVER (ORDER BY pc.distinct_procedure_count) AS quintile
    FROM procedure_counts pc
    INNER JOIN eligible_patients ep
        ON pc.subject_id = ep.subject_id
        AND pc.hadm_id = ep.hadm_id
        AND pc.stay_id = ep.stay_id
)
SELECT
    quintile,
    AVG(distinct_procedure_count) AS mean_procedure_count,
    AVG(icu_los_hours / 24.0) AS mean_icu_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality
FROM quintile_assignment
GROUP BY quintile
ORDER BY quintile;