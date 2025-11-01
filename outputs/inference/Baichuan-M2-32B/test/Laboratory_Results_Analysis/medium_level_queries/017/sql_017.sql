WITH eligible_admissions AS (
    SELECT DISTINCT
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 47 AND 57
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I25%'
        AND dd.long_title LIKE '%ischemic heart disease%'
),
troponin_t AS (
    SELECT
        le.hadm_id,
        le.subject_id,
        le.charttime,
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE
        dli.label LIKE '%Troponin-T%'
        AND dli.category = 'Cardiac'
        AND le.valueuom = 'ng/mL'
        AND le.valuenum > 0.014
),
first_troponin AS (
    SELECT
        t.hadm_id,
        t.valuenum
    FROM troponin_t t
    INNER JOIN eligible_admissions e
        ON t.hadm_id = e.hadm_id
        AND t.charttime BETWEEN e.admittime AND e.dischtime
    WHERE t.rn = 1
)
SELECT
    APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75
FROM first_troponin;