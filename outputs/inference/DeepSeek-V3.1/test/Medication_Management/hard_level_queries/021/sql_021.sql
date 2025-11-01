WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        -- Calculate LOS in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Check for 30-day readmission
        CASE WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` readm 
            WHERE readm.subject_id = adm.subject_id 
            AND readm.admittime > adm.dischtime 
            AND readm.admittime <= DATETIME_ADD(adm.dischtime, INTERVAL 30 DAY)
        ) THEN 1 ELSE 0 END AS readmit_30d
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 41 AND 51
        -- Neutropenia: at least one ANC < 1.5 during admission
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
                ON le.itemid = dli.itemid
            WHERE le.hadm_id = adm.hadm_id
                AND le.itemid = 51256  -- Absolute neutrophil count
                AND le.valuenum < 1.5
        )
        -- Fever: at least one temperature > 38°C during admission
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
            INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
                ON ce.itemid = di.itemid
            WHERE ce.hadm_id = adm.hadm_id
                AND ce.itemid = 223762  -- Temperature Celsius
                AND ce.valuenum > 38
        )
),

med_counts AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        COUNT(DISTINCT pr.drug) AS med_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON c.hadm_id = pr.hadm_id
    WHERE pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    GROUP BY c.subject_id, c.hadm_id
),

cohort_with_meds AS (
    SELECT 
        c.*,
        COALESCE(m.med_count, 0) AS med_count,
        NTILE(3) OVER (ORDER BY COALESCE(m.med_count, 0)) AS tertile
    FROM cohort c
    LEFT JOIN med_counts m
        ON c.hadm_id = m.hadm_id
)

SELECT 
    tertile,
    COUNT(*) AS n_patients,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
    ROUND(100 * AVG(readmit_30d), 2) AS readmit_30d_percent
FROM cohort_with_meds
GROUP BY tertile
ORDER BY tertile;