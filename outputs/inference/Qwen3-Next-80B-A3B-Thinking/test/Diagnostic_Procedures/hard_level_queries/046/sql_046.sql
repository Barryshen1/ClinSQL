WITH specific_group AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        i.stay_id,
        i.intime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
    WHERE p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND d.icd_code = 'J80'
            AND d.icd_version = 10
      )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) = 1
),
specific_group_procedures AS (
    SELECT
        sg.subject_id,
        COUNT(DISTINCT pe.itemid) AS procedure_count
    FROM specific_group sg
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON sg.stay_id = pe.stay_id
        AND pe.starttime BETWEEN sg.intime AND TIMESTAMP_ADD(sg.intime, INTERVAL 72 HOUR)
    GROUP BY sg.subject_id
),
all_icu_stays AS (
    SELECT
        i.stay_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
all_icu_procedures AS (
    SELECT
        a.stay_id,
        COUNT(DISTINCT pe.itemid) AS procedure_count
    FROM all_icu_stays a
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON a.stay_id = pe.stay_id
        AND pe.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    GROUP BY a.stay_id
)
SELECT
    MIN(sgp.procedure_count) AS min_procedures_specific,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY aip.procedure_count) AS p75_all,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY aip.procedure_count) AS p90_all,
    AVG(DATETIME_DIFF(ais.dischtime, ais.admittime, DAY)) AS mean_los,
    AVG(ais.hospital_expire_flag) AS mortality_rate
FROM specific_group_procedures sgp,
     all_icu_procedures aip,
     all_icu_stays ais;