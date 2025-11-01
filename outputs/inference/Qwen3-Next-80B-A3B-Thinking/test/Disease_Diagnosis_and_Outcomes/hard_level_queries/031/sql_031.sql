WITH cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.anchor_age,
        p.anchor_year
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 85 AND 95
),
asthma_diagnoses AS (
    SELECT
        d.subject_id,
        d.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE
        di.long_title LIKE '%asthma%' AND di.long_title LIKE '%exacerbation%'
),
cohort_asthma AS (
    SELECT
        c.*
    FROM
        cohort c
    JOIN
        asthma_diagnoses a
        ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
),
charlson_conditions AS (
    SELECT
        d.subject_id,
        d.hadm_id,
        MAX(CASE WHEN (d.icd_version = '9' AND (d.icd_code LIKE '410%' OR d.icd_code IN ('411.0', '411.1', '411.8', '411.9', '412')))
                 OR (d.icd_version = '10' AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
                 THEN 1 ELSE 0 END) AS mi,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code LIKE '428%')
                 OR (d.icd_version = '10' AND d.icd_code LIKE 'I50%')
                 THEN 1 ELSE 0 END) AS chf,
        MAX(CASE WHEN (d.icd_version = '9' AND (d.icd_code LIKE '440%' OR d.icd_code = '443.9'))
                 OR (d.icd_version = '10' AND (d.icd_code LIKE 'I70%' OR d.icd_code = 'I73.9'))
                 THEN 1 ELSE 0 END) AS pvd,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code BETWEEN '430' AND '438')
                 OR (d.icd_version = '10' AND d.icd_code BETWEEN 'I60' AND 'I69')
                 THEN 1 ELSE 0 END) AS cvd,
        MAX(CASE WHEN (d.icd_version = '9' AND (d.icd_code LIKE '290%' OR d.icd_code = '294.1'))
                 OR (d.icd_version = '10' AND (d.icd_code BETWEEN 'F01' AND 'F03' OR d.icd_code = 'G30'))
                 THEN 1 ELSE 0 END) AS dementia,
        MAX(CASE WHEN (d.icd_version = '9' AND (d.icd_code BETWEEN '490' AND '492' OR d.icd_code BETWEEN '494' AND '496'))
                 OR (d.icd_version = '10' AND (d.icd_code BETWEEN 'J40' AND 'J47' OR d.icd_code BETWEEN 'J60' AND 'J67'))
                 THEN 1 ELSE 0 END) AS cpd,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code LIKE '710%')
                 OR (d.icd_version = '10' AND (d.icd_code LIKE 'M05%' OR d.icd_code LIKE 'M06%'))
                 THEN 1 ELSE 0 END) AS rheumatic,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code BETWEEN '531' AND '534')
                 OR (d.icd_version = '10' AND d.icd_code BETWEEN 'K25' AND 'K28')
                 THEN 1 ELSE 0 END) AS peptic_ulcer,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code BETWEEN '570' AND '571')
                 OR (d.icd_version = '10' AND (d.icd_code LIKE 'K70%' OR d.icd_code LIKE 'K74%'))
                 THEN 1 ELSE 0 END) AS mild_liver,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code LIKE '250.0%')
                 OR (d.icd_version = '10' AND (d.icd_code LIKE 'E10.0%' OR d.icd_code LIKE 'E11.0%' OR d.icd_code LIKE 'E13.0%'))
                 THEN 1 ELSE 0 END) AS diabetes_no_comp,
        MAX(CASE WHEN (d.icd_version = '9' AND (d.icd_code LIKE '250.1%' OR d.icd_code LIKE '250.2%' OR d.icd_code LIKE '250.3%' OR d.icd_code LIKE '250.4%' OR d.icd_code LIKE '250.5%' OR d.icd_code LIKE '250.6%' OR d.icd_code LIKE '250.7%' OR d.icd_code LIKE '250.8%'))
                 OR (d.icd_version = '10' AND (d.icd_code LIKE 'E10.1%' OR d.icd_code LIKE 'E10.2%' OR d.icd_code LIKE 'E10.3%' OR d.icd_code LIKE 'E10.4%' OR d.icd_code LIKE 'E10.5%' OR d.icd_code LIKE 'E10.6%' OR d.icd_code LIKE 'E10.7%' OR d.icd_code LIKE 'E10.8%' OR
                                            d.icd_code LIKE 'E11.1%' OR d.icd_code LIKE 'E11.2%' OR d.icd_code LIKE 'E11.3%' OR d.icd_code LIKE 'E11.4%' OR d.icd_code LIKE 'E11.5%' OR d.icd_code LIKE 'E11.6%' OR d.icd_code LIKE 'E11.7%' OR d.icd_code LIKE 'E11.8%' OR
                                            d.icd_code LIKE 'E13.1%' OR d.icd_code LIKE 'E13.2%' OR d.icd_code LIKE 'E13.3%' OR d.icd_code LIKE 'E13.4%' OR d.icd_code LIKE 'E13.5%' OR d.icd_code LIKE 'E13.6%' OR d.icd_code LIKE 'E13.7%' OR d.icd_code LIKE 'E13.8%'))
                 THEN 1 ELSE 0 END) AS diabetes_comp,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code = '344.0')
                 OR (d.icd_version = '10' AND d.icd_code = 'G82.2')
                 THEN 1 ELSE 0 END) AS paraplegia,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code BETWEEN '585' AND '586')
                 OR (d.icd_version = '10' AND d.icd_code BETWEEN 'N18' AND 'N19')
                 THEN 1 ELSE 0 END) AS renal,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code BETWEEN '140' AND '208')
                 OR (d.icd_version = '10' AND d.icd_code BETWEEN 'C00' AND 'C97')
                 THEN 1 ELSE 0 END) AS malignancy,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code IN ('571.5', '571.6'))
                 OR (d.icd_version = '10' AND (d.icd_code LIKE 'K70.3%' OR d.icd_code LIKE 'K71.5%' OR d.icd_code LIKE 'K72.1%' OR d.icd_code LIKE 'K76.0%'))
                 THEN 1 ELSE 0 END) AS severe_liver,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code BETWEEN '196' AND '199')
                 OR (d.icd_version = '10' AND d.icd_code BETWEEN 'C77' AND 'C80')
                 THEN 1 ELSE 0 END) AS metastatic,
        MAX(CASE WHEN (d.icd_version = '9' AND d.icd_code = '042')
                 OR (d.icd_version = '10' AND d.icd_code = 'B20')
                 THEN 1 ELSE 0 END) AS aids
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    GROUP BY
        d.subject_id, d.hadm_id
),
charlson_scores AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        (mi * 1) +
        (chf * 1) +
        (pvd * 1) +
        (cvd * 1) +
        (dementia * 1) +
        (cpd * 1) +
        (rheumatic * 1) +
        (peptic_ulcer * 1) +
        (mild_liver * 1) +
        (diabetes_no_comp * 1) +
        (diabetes_comp * 2) +
        (paraplegia * 2) +
        (renal * 2) +
        (malignancy * 2) +
        (severe_liver * 3) +
        (metastatic * 6) +
        (aids * 6) AS charlson_score,
        CASE WHEN mi = 1 OR chf = 1 OR cvd = 1 THEN 1 ELSE 0 END AS cardiovascular_complication,
        CASE WHEN cvd = 1 OR dementia = 1 THEN 1 ELSE 0 END AS neurologic_complication
    FROM
        charlson_conditions c
),
quartiles AS (
    SELECT
        ca.hospital_expire_flag,
        cs.cardiovascular_complication,
        cs.neurologic_complication,
        cs.charlson_score,
        NTILE(4) OVER (ORDER BY cs.charlson_score) AS quartile
    FROM
        cohort_asthma ca
    JOIN
        charlson_scores cs
        ON ca.subject_id = cs.subject_id AND ca.hadm_id = cs.hadm_id
)
SELECT
    quartile,
    AVG(hospital_expire_flag) AS in_hospital_mortality,
    AVG(cardiovascular_complication) AS cardiovascular_complication_rate,
    AVG(neurologic_complication) AS neurologic_complication_rate
FROM
    quartiles
GROUP BY
    quartile
ORDER BY
    quartile;