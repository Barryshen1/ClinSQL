WITH base AS (
    SELECT 
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.discharge_location,
        adm.hospital_expire_flag,
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_adm
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND adm.admission_location LIKE '%HOSPITAL%'
        AND adm.admission_location LIKE '%TRANSFER%'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 63 AND 73
),
filtered AS (
    SELECT 
        hadm_id,
        admittime,
        dischtime,
        discharge_location,
        hospital_expire_flag,
        age_at_adm,
        CASE
            WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
            WHEN discharge_location LIKE '%HOSPICE%' THEN 'hospice'
            WHEN discharge_location LIKE '%HOME%' THEN 'discharged home'
            ELSE NULL
        END AS discharge_group
    FROM base
)
SELECT
    discharge_group,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*60*60)) AS mean_los,
    STDDEV(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*60*60)) AS sd_los
FROM filtered
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group
ORDER BY discharge_group;