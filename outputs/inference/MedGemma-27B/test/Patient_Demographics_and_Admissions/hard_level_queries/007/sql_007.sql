SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        a.hospital_expire_flag
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      WHERE
        a.admittime > (
          SELECT
            MAX(dischtime)
          FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
          WHERE
            a2.subject_id = a.subject_id
            AND a2.hadm_id < a.hadm_id
        )
        AND a.admittime <= TIMESTAMP_ADD(
          (
            SELECT
              MAX(dischtime)
            FROM
              `physionet-data.mimiciv_3_1_hosp.admissions` AS a3
            WHERE
              a3.subject_id = a.subject_id
              AND a3.hadm_id < a.hadm_id
          ),
          INTERVAL 30 DAY
        )
    );