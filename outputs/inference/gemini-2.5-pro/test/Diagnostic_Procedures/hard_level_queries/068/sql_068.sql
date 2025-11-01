WITH asthma_admissions AS (
    SELECT DISTINCT
        p.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
        ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    WHERE
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 77 AND 87
        AND (
            LOWER(ddx.long_title) LIKE '%asthma%exacerbation%'
            OR LOWER(ddx.long_title) LIKE '%status asthmaticus%'
        )
),

-- Step 2: For this cohort, find the first ICU stay for each hospital admission.
first_icu_stays AS (
    SELECT
        aa.hadm_id,
        icu.stay_id,
        icu.intime,
        aa.admittime,
        aa.dischtime,
        aa.hospital_expire_flag
    FROM
        asthma_admissions AS aa
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON aa.hadm_id = icu.hadm_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY aa.hadm_id ORDER BY icu.intime) = 1
),

-- Step 3: Count procedures performed in the first 72 hours of the ICU stay for each patient.
procedure_counts AS (
    SELECT
        fis.stay_id,
        -- COUNT(pe.itemid) will correctly return 0 for stays with no procedures due to the LEFT JOIN
        COUNT(pe.itemid) AS procedure_count
    FROM
        first_icu_stays AS fis
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
        ON fis.stay_id = pe.stay_id
        -- Filter procedures to the first 72 hours
        AND pe.starttime BETWEEN fis.intime AND DATETIME_ADD(fis.intime, INTERVAL 72 HOUR)
    GROUP BY
        fis.stay_id
),

-- Step 4: Combine stats and stratify patients into quartiles based on procedure count.
patient_quartiles AS (
    SELECT
        pc.procedure_count,
        DATETIME_DIFF(fis.dischtime, fis.admittime, HOUR) / 24.0 AS hospital_los_days,
        fis.hospital_expire_flag,
        NTILE(4) OVER (ORDER BY pc.procedure_count) AS procedure_quartile
    FROM
        first_icu_stays AS fis
    INNER JOIN
        procedure_counts AS pc
        ON fis.stay_id = pc.stay_id
)

-- Step 5: Calculate final metrics for each quartile.
SELECT
    pq.procedure_quartile,
    AVG(pq.procedure_count) AS mean_procedure_count,
    AVG(pq.hospital_los_days) AS mean_hospital_los_days,
    AVG(CAST(pq.hospital_expire_flag AS FLOAT64)) AS hospital_mortality
FROM
    patient_quartiles AS pq
GROUP BY
    pq.procedure_quartile
ORDER BY
    pq.procedure_quartile;