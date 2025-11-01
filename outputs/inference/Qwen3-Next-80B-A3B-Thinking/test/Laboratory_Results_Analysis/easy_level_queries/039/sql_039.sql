WITH male_pneumonia_admissions AS (
    SELECT DISTINCT di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON di.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND LOWER(dicd.long_title) LIKE '%pneumonia%'
),
peak_creatinine AS (
    SELECT l.hadm_id, MAX(l.valuenum) AS peak_creat
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
        ON l.itemid = dl.itemid
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON l.hadm_id = a.hadm_id
    WHERE LOWER(dl.label) LIKE '%creatinine%'
        AND l.charttime BETWEEN a.admittime AND a.dischtime
    GROUP BY l.hadm_id
)
SELECT STDDEV(peak_creat) AS std_dev_peak_creatinine
FROM male_pneumonia_admissions m
JOIN peak_creatinine pc
    ON m.hadm_id = pc.hadm_id;